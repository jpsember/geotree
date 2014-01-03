require 'tempfile'

module ExternalSortModule

  # Performs an external sort of a binary file.
  # Used by the GeoTree module to shuffle buffered point sets into a random
  # order prior to adding to the tree, in order to create a balanced tree.
  #
  class Sorter

    MAX_SEGMENTS = 8

    # Constructor
    # @param path of file to sort
    # @param element_size size, in bytes, of each element
    # @param comparator to compare elements; if nil, compares the bytes as substrings
    #
    def initialize(path, element_size, comparator=nil, max_chunk_size = MAX_CHUNK_SIZE_, max_segments = MAX_SEGMENTS)
      @comparator = comparator || Proc.new do |x,y|
        x <=> y
      end

      @path = path
      raise ArgumentError if max_segments < 2
      @max_segments = max_segments
      @aux_file = nil
      @element_size = element_size
      @main_file_len = File.size(path)
      @max_chunk_size = max_chunk_size - max_chunk_size % element_size
      raise ArgumentError if @max_chunk_size <= 0
      if @main_file_len == 0 || @main_file_len % element_size != 0
        raise ArgumentError,"File length #{@main_file_len} is not a positive multiple of element size #{element_size}"
      end
    end

    def sort
      segments = partition_files_into_segments
      @main_file = File.open(@path,IO::BINARY | IO::RDWR)

      sort_segments_in_place(segments)

      @aux_file = Tempfile.new('_externalsort_')
      @aux_file.binmode
      # The algorithm should not be attempting to write beyond the current end of the aux file.
      # We'll keep track of the file length to verify this.
      @aux_file_length = 0

      merge_segments(segments)

      @aux_file.unlink
      @main_file.close
    end


    private


    # Partition the file into segments, each no bigger than a chunk
    #
    def partition_files_into_segments
      segments = []
      off = 0
      while off < @main_file_len
        seg_len = [@main_file_len - off, @max_chunk_size].min
        segments << [off, seg_len]
        off += seg_len
      end
      segments
    end

    # Sort the elements within each segment
    #
    def sort_segments_in_place(segments)
      segments.each{|offset,length| sort_segment_entries(@main_file,offset,length)}
    end

    def sort_segment_entries(file,offset,length)
      chunk_data = ChunkReader.read_from_file(file,offset,length)
      chunk = Chunk.new(chunk_data, @element_size)

      # Choose an ordering for these elements
      order =  (0 ... chunk.number_of_elements).to_a
      order.sort! do |x,y|
        ex = chunk.read_element(x)
        ey = chunk.read_element(y)
        @comparator.call(ex,ey)
      end

      # Construct another chunk, where we will copy the sorted elements
      sorted_chunk = Chunk.new(ByteArray.zeros(length),@element_size)
      j = 0
      order.each do |i|
        sorted_chunk.write_element(j,chunk.read_element(i))
        j += 1
      end

      ChunkWriter.write_to_file(file,offset,sorted_chunk.contents)
    end

    # Merge segments into one; if too many to handle at once, process recursively
    def merge_segments(segments)

      return segments if segments.size <= 1

      if segments.size > @max_segments
        merge_segments_recursively(segments)
      else
        segset_start,segset_length = determine_merged_segment_size(segments)

        chunk_readers = build_segment_chunk_readers(segments)
        merge_segments_to_aux_file(segset_start,segset_length,chunk_readers)
        copy_merged_entries_from_aux_file(segset_start,segset_length)

        [[segset_start,segset_length]]
      end
    end

    def merge_segments_recursively(segments)
      k = segments.size/2
      s1 = segments[0 .. k-1]
      s2 = segments[k .. -1]
      segments = merge_segments(s1)
      segments.concat(merge_segments(s2))
      return merge_segments(segments)
    end

    def determine_merged_segment_size(segments)
      segments_length = 0
      segments_start = nil
      segments.each do |sg|
        offset,len = sg
        segments_start ||= offset
        segments_length += len
      end
      [segments_start,segments_length]
    end

    def build_segment_chunk_readers(segments)
      chunk_readers = []
      segments.each do |sg|
        off,len = sg
        ch = ChunkReader.new(@main_file, off, len, @element_size, @max_chunk_size)
        # puts "built chunk reader offset #{off} length #{len}"
        chunk_readers << ch
      end
      # puts("build_segment_chunk_readers, built #{chunk_readers}")
      chunk_readers
    end

    def merge_segments_to_aux_file(segments_offset,segments_length,chunk_readers)
      sort_segment_chunk_readers(chunk_readers)

      # Build a chunk for writing merged result to the aux file

      raise IllegalStateException if segments_offset > @aux_file_length
      @aux_file_length = [@aux_file_length,segments_offset+segments_length].max

      writer = ChunkWriter.new(@aux_file,segments_offset, @element_size, @max_chunk_size)

      while !chunk_readers.empty?
        reader = chunk_readers.pop
        writer.write(reader.read)
        next if !reader.peek
        insert_chunk_reader_into_sorted_array(reader,chunk_readers)
      end
      writer.flush
    end

    def insert_chunk_reader_into_sorted_array(chunk_reader,array)
      chunk_peek = chunk_reader.peek
      insert_position = array.index{|x| @comparator.call(x.peek,chunk_peek) < 0}
      insert_position ||= array.length
      array.insert(insert_position,chunk_reader)
    end

    # Sort the chunks into order by their peek items, so the lowest item is at the end of the array
    #
    def sort_segment_chunk_readers(array)
      a = []
      array.each{|x| insert_chunk_reader_into_sorted_array(x,a)}
      array.replace(a)
    end

    # Read the now-sorted entries from the aux file to the merged segment
    #
    def copy_merged_entries_from_aux_file(segset_start,segset_length)
      reader = ChunkReader.new(@aux_file,segset_start,segset_length,@element_size,@max_chunk_size)
      writer = ChunkWriter.new(@main_file,segset_start,@element_size,@max_chunk_size)
      while true
        element = reader.read
        break if !element
        writer.write(element)
      end
      writer.flush
    end

  end

end # module

