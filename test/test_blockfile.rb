#!/usr/bin/env ruby
require 'geotree'
require 'js_base/test'

class TestBlockFile < Test::Unit::TestCase

  def setup
    enter_test_directory
    @bf = nil
  end

  def teardown
    leave_test_directory
  end

  def build_bf
    if !@bf
      @bf = BlockFile.new(64)
    end
  end


  # --------------- tests --------------------------

  def test_100_create_block_file
    build_bf
    assert(@bf && !@bf.open?)
  end
  def test_110_create_and_open_block_file
    build_bf
    @bf.open
    assert(@bf &&   @bf.open?)
  end

  def test_120_user_values
    build_bf
    @bf.open
    k = 42
    @bf.write_user(2,k)
    @bf.write_user(1,k/2)
    assert(@bf.read_user(2) == k)
    assert(@bf.read_user(1) == k/2)
  end

  def test_130_read_when_not_open
    assert_raise(IllegalStateException) do
      build_bf
      @bf.write_user(2,42)
    end
  end

  def test_140_private_constant_access
    assert_raise(NameError) do
      BlockFile::BLOCKTYPE_RECYCLE
    end
  end


  def _test_string_manip
    chunk_size = 512
    nchunks = 2000
    data_size = chunk_size * nchunks

    s1 = "A" * data_size
    s2 = "B" * data_size
    nchunks.times do |k|
      puts("k=#{k}")
      i = k*chunk_size
      sl = s1[i...i+chunk_size]
      s2[i...i+chunk_size] = sl
    end
  end

  def _test_byte_stuff
    s = "A"*1024
    a = [65] * 1024

    path = '_binary1_.txt'
    f = File.open(path,"w+b")
    count = f.write(s)
    f.close
    puts "wrote string, count=#{count}"
    r1 = FileUtils.read_text_file(path)
    puts("read:#{r1}")

path = '_binary2_.txt'

    f = File.open(path,"w+b")

    s2 = a.pack('C*')
    count = f.write(s2)
    f.close
    puts "wrote bytes, count=#{count}"
    r2 = FileUtils.read_text_file(path)
    puts("read:#{r2}")

  end

end

