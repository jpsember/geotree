#!/usr/bin/env ruby
require 'geotree'
require 'js_base/test'

class TestByteArray < Test::Unit::TestCase

  def setup
  end

  def teardown
  end

  def str(s)
    s.force_encoding(Encoding::ASCII_8BIT)
  end

  def build(length, value)
    c = str(value.chr)
    a = ByteArray.new(length)
    a.string[0...length] = c * length
    a
  end

  def test_bytes_to_string
    assert_equal(ByteArray.bytes_to_string([0,1,127,128,254,255]), str("\x00\x01\x7f\x80\xfe\xff"))
    assert_equal(ByteArray.bytes_to_string([]),str(""))
  end

  def test_new
    a = ByteArray.new(5)
    assert_equal(a.string,str("\x00"*5))
  end

  def test_read
    a = build(10,8)
    a.string[3,4] = ByteArray.bytes_to_string([40,41,42,43])
    x = a.read(2,6)
    assert_equal(x,ByteArray.bytes_to_string([8,40,41,42,43,8]))
  end

  def test_write
    a = build(10,8)
    b = build(10,14)
    ByteArray.copy(a,1,8,b,1)
    assert_equal(b.string,ByteArray.bytes_to_string([14,8,8,8,8,8,8,8,8,14]))
  end

  def test_write_int
    v = [-3,1234,-10000,5_000_000,-5_000_000]
    a = build(v.size*4,0)
    v.each_with_index{|x,i| a.write_int(i,x)}
    v.each_with_index{|x,i| assert_equal(x,a.read_int(i))}
  end

  def test_copy_to
    a = build(10,77)
    b = build(10,66)

    a_orig = a.string.dup

    a.copy_to(b)
    assert_equal(b.string,ByteArray.bytes_to_string([77]*10))

    b.write_int(0,1234)
    assert_equal(a.string,a_orig)
  end

end

