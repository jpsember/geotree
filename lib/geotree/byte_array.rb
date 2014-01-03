# Abstracts arrays of bytes; they are stored as ASCII_8BIT strings internally,
# but since Ruby 1.9 and Unicode support this has become confusing.

class ByteArray

  @@zero_string = "\0".encode(Encoding::ASCII_8BIT)

  # Construct a string containing a number of zeros
  #
  def self.zeros(length)
    @@zero_string * length
  end

  # Convert an array of bytes to a string
  #
  def self.bytes_to_string(byte_array)
    byte_array.pack('c*')
  end

  # Constructor
  # If arg is a string, it's used as the content;
  # otherwise, it's assumed to be an integer, and the content is set to this number of zeros
  #
  def initialize(size_or_string)
    if size_or_string.is_a? String
      @content = size_or_string
    else
      @content = ByteArray.zeros(size_or_string)
    end
  end

  def clear
    @content[0..-1] = ByteArray.zeros(@content.size)
  end

  def read(offset, length)
    @content[offset, length]
  end

  def write(source, source_offset, length, destination_offset)
    if source.is_a? Array
      source = ByteArray.bytes_to_string(source[source_offset,length])
      source_offset = 0
    end
    @content[destination_offset,length] = source[source_offset,length]
  end

  def string
    @content
  end

  def size
    @content.size
  end

  INT_BYTES_ = 4

  # Read an integer; offset is integer number, where each integer occupies 4 bytes
  def read_int(int_offset)
    j = int_offset*INT_BYTES_

    # We must treat the most significant byte as a signed byte
    high_byte = @content[j].ord
    if high_byte > 127
      high_byte = high_byte - 256
    end
    (high_byte << 24) | (@content[j+1].ord << 16) | (@content[j+2].ord << 8) | @content[j+3].ord
  end

  # Write an integer
  def write_int(int_offset, value)
    j = int_offset * INT_BYTES_
    @content[j] = ((value >> 24) & 0xff).chr
    @content[j+1] = ((value >> 16) & 0xff).chr
    @content[j+2] = ((value >> 8) & 0xff).chr
    @content[j+3] = (value & 0xff).chr
  end

  def copy_to(dest_array)
    ByteArray.copy(self,0,@content.size,dest_array,0)
  end

  def write_string(str, dest_offset)
    @content[dest_offset,str.length] = str
  end

  def read_string(offset,length)
    @content[offset,length]
  end

  def self.copy(source,source_offset,length,dest,dest_offset)
    dest.string[dest_offset,length] = source.string[source_offset,length]
  end

end
