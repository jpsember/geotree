module ExternalSortModule

class ChunkReader

  DEFAULT_WINDOW_SIZE = 2048

  def inspect
    "\nChunkReader target base #{@target_base} window base #{@window_base} cursor #{@window_cursor} peek #{peek.inspect}"
  end

  def self.read_from_file(file,offset,length)
      file.pos = offset
      data = file.read(length)
      raise IOError if !data || data.length != length
      data
  end

  def initialize(target_file, target_offset, target_length, element_size, window_size = DEFAULT_WINDOW_SIZE)
    @target_file = target_file
    @element_size = element_size
    window_size -= (window_size % element_size)
    raise ArgumentError if window_size <= 0
    raise ArgumentError if target_length % element_size != 0

    @window_maximum_size = window_size

    @target_length = target_length
    @target_base = target_offset

    @window_base = 0
    @window_cursor = 0
    @window_contents = ''

  end

  # @return element or nil if none remain
  def peek
    return nil if @window_base + @window_cursor == @target_length

    if @window_cursor == @window_contents.length
      @window_base += @window_contents.length
      window_size = [@window_maximum_size,@target_length - @window_base].min
      @window_cursor = 0
      @window_contents = ChunkReader.read_from_file(@target_file,@target_base + @window_base,window_size)
    end

    @window_contents[@window_cursor,@element_size]
  end

  # @return element or nil if none remain
  def read
    element = peek
    @window_cursor += @element_size if element
    element
  end

end

end # module
