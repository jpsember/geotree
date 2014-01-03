# Block file.
#
# For storing data in a collection of 'blocks', fixed-length arrays of bytes,
# with facility for recycling blocks that are no longer used.
#
# Base class is in-memory only; subclass to persist blocks, e.g., to a file system.
# The DiskBlockFile class does exactly this.
#
# Each block has a unique 'name'.  This is a positive integer.  The word 'name' is
# chosen instead of 'id' to avoid conflicting with the use of 'id' in some languages.
#
# Each block file header includes space for four integers, for use by the application.
#
class BlockFile

  FIRST_BLOCK_ID = 2
  USER_HEADER_INTS = 4

  VERSION_ = 1965

  # Size of blocks, in bytes
  attr_reader  :block_size

  # Constructor.  Constructs a file, initially closed.
  # @param block_size size of blocks, in bytes
  def initialize(block_size)
    block_size = [block_size, HDR_SIZE_BYTES_].max

    @block_size = block_size
    @header_data = nil
    @recycle_data = nil
    @header_modified = false

    # for in-memory version only:
    @mem_file = nil
  end

  # Determine if file is open
  def open?
    return @header_data != nil
  end

  # Open file.  Creates underlying storage if necessary.
  # File must not already be open.
  # @return true if underlying storage already existed
  #
  def open
    !open? || raise(IllegalStateException)
    existed = open_storage
    if !existed
      @header_data = alloc_buffer
      @header_data.write_int(HDR_VERSION_, VERSION_)
      @header_data.write_int(HDR_BLOCKSIZE_, block_size)
      @header_data.write_int(HDR_RECYCLEINDEX_, 1)
      append_or_replace(0, @header_data)

      @recycle_data = alloc_buffer
      append_or_replace(rdir_head_name, @recycle_data)

      aux_flush
    else
      @header_data = read(0)
      raise ArgumentError,"bad version" if @header_data.read_int(HDR_VERSION_) != VERSION_
      raise ArgumentError,"unexpected block size" if @header_data.read_int(HDR_BLOCKSIZE_) != block_size
      @recycle_data = read(rdir_head_name)
    end
    existed
  end

  # Allocate a new block.  First block allocated will have name = FIRST_BLOCK_ID.
  # @param src block data to write; if null, allocates and writes zeros
  # @return name of block
  #
  def alloc(src = nil)

    ensure_open

    src ||= alloc_buffer

    # get index of last recycle block directory
    r_index = rdir_head_name

    # any entries remain in this directory?
    n_ent = get_rdir_slots_used

    if n_ent == 0
      prev_rb_block = get_rdir_next_name

      if prev_rb_block > 0
        # use directory as new block
        ret = r_index
        r_index = prev_rb_block
        write_hdr(HDR_RECYCLEINDEX_, r_index)
        read(prev_rb_block, @recycle_data)
        append_or_replace(ret, src)
      else
        ret = name_max
        append_or_replace(ret, src)
      end
    else
      slot = n_ent - 1;
      ret = get_rdir_slot(slot)
      set_rdir_slot(slot,0)
      set_rdir_slots_used(slot)
      append_or_replace(r_index, @recycle_data)
      append_or_replace(ret,src)
    end
    ret
  end

  # Free up a block
  def free(block_name)
    ensure_open

    raise(ArgumentError,"no such block: #{block_name}") if block_name >=  name_max

    slot = get_rdir_slots_used()

    # if there is a free slot in the current recycle block, use it

    if slot < get_rdir_capacity
      set_rdir_slot(slot,block_name)
      set_rdir_slots_used(slot+1)
      append_or_replace(rdir_head_name, @recycle_data)
    else
      # use freed block as next recycle page
      old_dir = rdir_head_name

      write_hdr(HDR_RECYCLEINDEX_, block_name)

      read(block_name, @recycle_data)
      @recycle_data.clear

      set_rdir_next_name(old_dir)
      append_or_replace(block_name, @recycle_data)
    end
  end

  def close
    ensure_open
    aux_flush
    close_storage

    @header_data = nil
    @recycle_data = nil
    @mem_file = nil
  end

  # Read one of the user values from the header
  # @param int_index index of user value (0..3)
  def read_user(int_index)
    ensure_open
    raise ArgumentError if !(int_index >= 0 && int_index < USER_HEADER_INTS)
    @header_data.read_int(HDR_USERSTART_ + int_index)
  end

  # Write a user value
  # @param int_index index of user value (0..3)
  # @param value value to write
  def write_user(int_index, value)
    ensure_open
    raise ArgumentError if !(int_index >= 0 && int_index < USER_HEADER_INTS)
    @header_data.write_int(HDR_USERSTART_ + int_index, value)
    @header_modified = true
  end

  def inspect
    to_s
  end

  def to_s
    s = ''
    s << "BlockFile blockSize:#{block_size} "
    if open?
      s << "\n name_max=#{name_max}"
      s << "\n rdir_head_name=#{rdir_head_name}"

      s << "\n"

      # Dump a map of currently allocated blocks
      usage = {}
      usage[0] = 'H'
      ri = rdir_head_name
      while ri != 0
        usage[ri] = 'R'
        rd = read(ri)

        next_ri = rd.read_int(RC_PREV_DIR_NAME_)
        used = rd.read_int(RC_ENTRIES_USED_)
        used.times do |i|
          rblock = read_int(RC_ENTRIES_START_+i)
          usage[rblock] = 'r'
        end
        ri = next_ri
      end

      row_size = 64

      puts("------------- Block Map --------------")
      name_max.times do |i|
        if (i % row_size) == 0
          printf("%04x: ",i)
        elsif (i % 4 == 0)
          print('  ')
        end
        label = usage[i]
        label ||= '.'
        print label
        print "\n" if ((i+1) % row_size) == 0
      end
      print "\n" if (name_max % row_size != 0)
      puts("--------------------------------------")
    end
    s
  end

  # Create an array of bytes, all zeros, of length equal to this block file's block length
  def alloc_buffer
    ByteArray.new(@block_size)
  end

  # -------------------------------------------------------
  # These methods should be overridden by subclasses
  # for block files that are not to be memory-only (as
  # the default implementations assume)

  # Read block from storage.
  # @param block_name index of block
  # @param dest_buffer where to store data; if nil, you should
  #   call alloc_buffer to create it
  # @return buffer
  #
  def read(block_name, dest_buffer = nil)
    dest_buffer ||= alloc_buffer
    if block_name >= @mem_file.size
      raise ArgumentError,"No such block name #{block_name} exists (size=#{@mem_file.size})"
    end

    src = @mem_file[block_name]
    ByteArray.copy(src,0,@block_size,dest_buffer,0)
    dest_buffer
  end

  # Write block to storage.
  # Name is either index of existing block, or
  #  number of existing blocks (to append to end of existing ones)
  # @param block_name name of block
  # @param src_buffer data to write
  def write(block_name, src_buffer)
    if  block_name == @mem_file.size
      @mem_file << alloc_buffer
    end
    dest = @mem_file[block_name]
    ByteArray.copy(src_buffer,0,@block_size,dest,0)
  end

  # Open underlying storage; create it if necessary
  # @return true if underlying storage already existed
  def open_storage
    @mem_file = []
    false
  end

  # Close underlying storage
  #
  def close_storage
    @mem_file = nil
  end

  # Flush underlying storage
  #
  def flush
  end

  # -------------------------------------------------------

  # Get 1 + name of highest block ever created
  def name_max
    @header_data.read_int(HDR_MAXINDEX_)
  end


  private


  def aux_flush
    if @header_modified
      append_or_replace(0, @header_data)
      @header_modified = false
    end
    flush
  end

  def ensure_block_exists(name)
    raise(ArgumentError,"no such block: #{name} (name_max=#{name_max})") if block_name >= name_max
  end

  def ensure_open
    raise IllegalStateException if !open?
  end

  # Determine how many names can be stored in a single
  # recycle directory block
  #
  def get_rdir_capacity
    (@block_size / INT_BYTES_) - RC_ENTRIES_START_
  end

  def get_rdir_slots_used
    @recycle_data.read_int(RC_ENTRIES_USED_)
  end

  def set_rdir_slots_used(n)
    @recycle_data.write_int(RC_ENTRIES_USED_,n)
  end

  # Get name of next recycle directory block
  # @return name of next, or 0 if there are no more
  def get_rdir_next_name
    @recycle_data.read_int(RC_PREV_DIR_NAME_)
  end

  def get_rdir_slot(offset)
    @recycle_data.read_int(RC_ENTRIES_START_+offset)
  end

  def set_rdir_slot(offset, value)
    @recycle_data.write_int(RC_ENTRIES_START_+offset,value)
  end

  def set_rdir_next_name(n)
    @recycle_data.write_int(RC_PREV_DIR_NAME_,n)
  end

  # Get name of first recycle directory block (they are connected as
  # a singly-linked list)
  #
  def rdir_head_name
    @header_data.read_int(HDR_RECYCLEINDEX_)
  end

  # Write a block; if we're appending a new block, increment
  # the name_max field
  #
  def append_or_replace(block_name, src)
    if (block_name < 0 || block_name > name_max)
      raise ArgumentError,"write to nonexistent block #{block_name}; only #{name_max} in file"
    end

    if block_name == name_max
      write_hdr(HDR_MAXINDEX_, block_name+1)
    end

    write(block_name, src)
  end

  # Write a value to a header field, mark header as modified
  # @param field field number (HDR_xxx)
  # @param value value to write
  #
  def write_hdr(field, value)
    @header_data.write_int(field, value)
    @header_modified = true
  end


  # Header block fields; each is an integer
  INT_BYTES_ = 4
  HDR_BLOCKSIZE_ = 1
  HDR_MAXINDEX_ = 2
  HDR_RECYCLEINDEX_ = 3
  HDR_USERSTART_ = 4
  HDR_SIZE_BYTES_ = (HDR_USERSTART_ + USER_HEADER_INTS) * INT_BYTES_

  # Fields of a recycle directory block
  RC_PREV_DIR_NAME_ = 0
  RC_ENTRIES_USED_ = 1
  RC_ENTRIES_START_ = 2
  HDR_VERSION_ = 0

end
