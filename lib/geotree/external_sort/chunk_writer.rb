module ExternalSortModule

class ChunkWriter

  def self.write_to_file(file,offset,string_to_write)
    file.pos = offset
    bytes_written = file.write(string_to_write)
    raise IOError if string_to_write.length != bytes_written
  end

  def initialize(target_file, target_offset, element_size, window_size)
    @target_file = target_file
    @element_size = element_size
    @window_maximum_size = window_size

    @target_base = target_offset

    @window_base = 0
    @window_cursor = 0
    @window_contents = ByteArray.zeros(window_size)
  end

  def flush
    if @window_cursor != 0
      ChunkWriter.write_to_file(@target_file,@window_base + @target_base,@window_contents[0,@window_cursor])
      @window_base += @window_cursor
      @window_cursor = 0
    end
  end

  # Write next element
  def write(element)
    if @window_cursor == @window_maximum_size
      flush
    end
    @window_contents[@window_cursor,@element_size] = element
    @window_cursor += @element_size
  end

end

end # module

