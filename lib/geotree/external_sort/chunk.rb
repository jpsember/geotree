module ExternalSortModule

  MAX_CHUNK_SIZE_ = 80 #500_000 #4_000_000

  # Base class for chunking file access.
  # Essentially a buffer that acts as a sliding window into a binary file.
  #
  class Chunk

    # Constructor
    # @param content_string contents of chunk (an ASCII_8BIT string of bytes)
    # @param element_size size of each element; string length must be multiple of this
    #
    def initialize(content_string, element_size)
      raise ArgumentError if content_string.length % element_size != 0

      @buffer = content_string
      @buffer_offset = 0
      @element_size = element_size
    end

    def contents
      @buffer
    end

    def number_of_elements
      @buffer.length / @element_size
    end

    def read_element(index)
      @buffer[index * @element_size,@element_size]
    end

    def write_element(index,element)
      @buffer[index * @element_size,@element_size] = element
    end

  end

end
