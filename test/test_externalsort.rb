#!/usr/bin/env ruby
require 'geotree'
require 'js_base/test'

class TestExternalSort <  Test::Unit::TestCase
  include ExternalSortModule

  ELEM_SIZE = 16

  def setup
    @swizzler = Swizzler.new
    @swizzler.shorten_backtraces

    srand(42)

    enter_test_directory

    @path =  "sample_file.bin"

    @comparator1 = Proc.new do |x,y|
      x <=> y
    end
    @comparator2 = Proc.new do |x,y|
      y <=> x
    end

    construct_test_file(@path,16_000)
  end

  def teardown
    leave_test_directory
    @swizzler.remove_all
  end

  ELEMENT_CHARS = 'ABCDEFGHIJKLMNOP'.split('')

  DEFAULT_ELEMENT_GENERATOR = Proc.new do |index|
    a = ELEMENT_CHARS.dup.shuffle
    a.join
  end

  def construct_test_file(path,num_elements,element_generator=DEFAULT_ELEMENT_GENERATOR)
    FileUtils.rm_rf(path)
    File.open(path,"wb") do |file|
      num_elements.times do |i|
        element = element_generator.call(i)
        if element.length < ELEM_SIZE
          element += ByteArray.zeros(ELEM_SIZE-element.length)
        end
        element[ELEM_SIZE-1..-1] = "\n"
        file.write(element)
      end
    end
  end

  def verify_sorted_order(path, comparator)
    length = File.size?(path)
    f = File.open(path,IO::BINARY | IO::RDONLY)
    r = ChunkReader.new(f,0,length,ELEM_SIZE,1000)
    prev_element = nil
    while true
      element = r.read
      break if !element
      if prev_element
        result = comparator.call(prev_element,element)
        assert(result <= 0, "Items not in expected order:\n#{prev_element}\n#{element}\n")
      end
      prev_element = element
    end
  end

  def build_sorter(path,comparator)
    Sorter.new(path,ELEM_SIZE,comparator)
  end


  def test_100_chunk
    path2 = '_copy_.bin'
    f = File.open(@path,"rb")
    f2 = File.open(path2,"wb")

    ch = ChunkReader.new(f,0,File.size(@path),ELEM_SIZE,73)
    ch2 = ChunkWriter.new(f2,0,ELEM_SIZE,300)

    while true
      element = ch.read()
      break if !element
      ch2.write(element)
    end
    ch2.flush
    assert(FileUtils.cmp(@path,path2))
  end

  def test_200_sort
    path2 = '_copy_.bin'
    [2,3,8,30].each do |max_segments|
      FileUtils.cp(@path,path2)
      chunk_size = (max_segments > 10) ? ELEM_SIZE*4 : 2000
      sr = Sorter.new(path2, ELEM_SIZE, nil, chunk_size, max_segments)
      sr.sort
      verify_sorted_order(path2,@comparator1)
    end
  end

  def test_300_sort_with_duplicates
    num_elements = 5_000
    generator = Proc.new do |index|
      a = ELEMENT_CHARS[0..5].dup.shuffle
      a.join
    end

    path = @path
    construct_test_file(path,num_elements,generator)
    sr = build_sorter(path,@comparator2)
    sr.sort
    verify_sorted_order(path,@comparator2)
    assert_equal(File.size(path),num_elements * ELEM_SIZE)
  end

  def _test_400_sort_large
    path = "_large_file_.bin"
    construct_test_file(path,300_000)
    sr = build_sorter(path,@comparator2)
    sr.sort
    verify_sorted_order(path,@comparator2)
  end

end
