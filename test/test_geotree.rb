#!/usr/bin/env ruby
require 'geotree'
require 'js_base/test'

include GeoTreeModule

class TestGeoTree <  Test::Unit::TestCase

  def setup
    @swizzler = Swizzler.new
    # @swizzler.shorten_backtraces

    enter_test_directory

    @tree_path = '_mytree_.dat'
    @t = nil

    @pts = []
    srand(7)

    n_pts = 20 #3000
    @pts << DataPoint.rnd_many(n_pts)

    p2 = DataPoint.rnd_many(n_pts/4)
    i = 0
    while i < p2.size
      n = [p2.size-i, 200].min
      pi = p2[i]
      (i...i+n).each do |j|
        pj = p2[j]
        pj.loc.set_to(pi.loc)
      end
      i += n
    end
    p2.shuffle!

    @pts << p2

    p3 = DataPoint.rnd_many(n_pts)
    p3.each_with_index do |pt,j|
      pt.loc=Loc.new(j*5,j*5)
    end
    @pts << p3

    srand(2000)
    @rects = Bounds.rnd_many(20)

  end

  def teardown
    leave_test_directory
    @swizzler.remove_all
  end

  def rnd_subset(pts, frac = 0.3)
    raise ArgumentError if pts.empty?

    a = pts.dup
    num = [(a.size * frac).to_i.ceil,a.size].min
    srand(1977)
    a.shuffle!
    del = a.slice!(0..num)
    rem = a
    [del,rem]
  end

  def pt_set(set = 0)
    assert(set < @pts.size  )
    @pts[set]
  end

  def tree
    @t ||= GeoTree.open(@tree_path)
  end

  def add_pts(set = 0, max_pts = 0)
    ps = @pts[set]
    if max_pts > 0
      ps = ps[0,max_pts]
    end
    ps.each{|dp| tree.add(dp)}
    tree.buffering = false
  end



  # Construct list of data points lying within a rectangle
  def pts_within_rect(pts,r)
    pts.select{|pt| r.contains_point(pt.loc)}
  end

  def names(pt_list)
    DataPoint.name_list(pt_list)
  end

  def query(tree, b, pts = nil)
    pts ||= pt_set

    f1 = names(tree.find(b))
    f2 = names(pts_within_rect(pts,b))

    if (!(f1 == f2))
      raise IllegalStateException, "Query tree, bounds #{b}, expected #{f2}, got #{f1}"
    end
  end

  def plot_pts(w,pts,gray=0)
    w.push(w.set_gray(gray))
    plot_pts_colored(w,pts)
    w.pop
  end

  def plot_pts_colored(w,pts,scale=1)
    pts.each do |pt|
      w.draw_disc(pt.loc.x,pt.loc.y,scale*0.3*(pt.weight+4))
    end

  end

  def pt_on_circle(cx,cy,ang,rad)

    x = cx + Math.cos(ang) * rad
    y = cy + Math.sin(ang) * rad
    Loc.new(x.to_i,y.to_i)
  end

  def prepare_tree(tree)

    ps1 = pt_set(0).dup
    ps1 = ps1[0,120]

    srand(42)
    ps2 = DataPoint.rnd_many(400)
    ps2.each do |pt|
      rs = rand*rand*500
      pc = pt_on_circle(820,620,rand * 2*3.1415,rs)
      pt.loc = pc
    end
    ps1.concat(ps2)

    ps1.each{|x| tree.add(x)}
    ps1
  end

  def prepare_ws(path)
    b = Bounds.new(0,0,1000,1000)

    w = PSWriter.new(path)

    w.set_logical_page_size(b.w,b.h)

    w
  end

  def test_create_tree
    tree
  end

  def test_add_points
    tree
    add_pts
  end

  def test_queries
    tree
    add_pts
    bn = @rects
    bn.each{|b| query(tree,b)}
  end

  def test_remove
    tree
    @pts.each_with_index do |pset,i|

      # Use buffering, since some point sets are very unbalanced
      tree.buffering = true
      add_pts(i)

      pts = pset
      while !pts.empty?

        del, rem = rnd_subset(pts)

        if !del.empty?
          # construct a copy of the first point to be removed, one with a slightly
          # different location, to verify that it won't get removed
          pt = del[0]
          loc = pt.loc
          while true
            x = loc.x + rand(3)-1
            y = loc.y + rand(3) - 1
            break if x!=loc.x || y != loc.y
          end

          pt = DataPoint.new(pt.name, pt.weight, Loc.new(x,y))
          pt2 = tree.remove(pt)
          assert(!pt2)
        end

        del.each  do |p|
          dp = tree.remove(p)
          assert(dp,"failed to remove #{p}")
        end

        # try removing each point again to verify we can't
        del.each  do |p|
          dp = tree.remove(p)
          assert(!dp)
        end
        pts = rem
      end

    end
  end

  def test_buffering
    tree

    tree.buffering = true
    add_pts(2)
    stat1 =   tree.statistics
    assert(stat1['leaf_depth (avg)'] < 2.6)
  end

  # Test using points expressed in terms of longitude(x) and latitude(y)
  def test_latlong
    t = tree

    pts = []

    pts << Loc.new(57.9,-2.9) # Aberdeen
    pts << Loc.new(19.26,-99.7) # Mexico City
    pts << Loc.new(-26.12,28.4) # Johannesburg

    pts.each_with_index do |pt,i|
      t.add(DataPoint.new(1+i,0,pt))
    end

    pts.each_with_index do |lc,i|
      y,x = lc.latit, lc.longit
      b = Bounds.new(x-1,y-1,2,2)

      r = t.find(b)
      assert(r.size == 1)
    end

  end

  def test_latlong_range_error
    assert_raise(ArgumentError) do
      Bounds.new(175.0,50,10,10)
    end
  end

  def test_open_and_close

    t = tree
    ps = pt_set(0)

    ps.each  do |dp|
      t.add(dp)
    end

    t.close
    @t = nil

    t = tree
    ps2 = t.find(GeoTree.max_bounds)

    assert(ps2.size == ps.size)
  end


  def test_ps_output

    tree = GeoTree.new

    all_points = prepare_tree(tree)
    w = prepare_ws("../geo_tree.ps")

    bgnd = nil

    50.times do |i|
      w.new_page("GeoTree")

      a = i * 3.1415/18
      rad = 30+i*8

      pp = pt_on_circle(500,450,a,rad)
      x = pp.x
      y = pp.y

      width = (200 * (20+i)) / 25
      height = (width * 2)/3

      r = Bounds.new(x-width/2,y-height/2,width,height)

      query(tree,r,all_points)

      found_points = tree.find(r)
      w.push(w.set_gray(0))
      w.draw_rect(r.x,r.y,r.w,r.h  )
      w.pop

      if !bgnd
        w.start_buffer

        w.push(w.set_rgb(0.4,0.4,0.9))
        plot_pts_colored(w,all_points)
        w.pop
        bgnd = w.stop_buffer
        w.add_element('bgnd',bgnd)
      end

      w.draw_element('bgnd')

      w.push(w.set_rgb(0.75,0,0))
      plot_pts_colored(w,found_points,1.5)
      w.pop

    end

    w.close();
  end


  def test_ps_output_multi

    tree_path = '_multitree_'

    # Perform two passes.  On the first,
    # create the multitree and the points;
    # on the second, open the tree and
    # construct a plot.

    ps1 = nil

    bgnd = nil

    [0,1].each do |pass|

      if pass == 0
        FileUtils.rm_rf(tree_path)
      else
        assert(File.directory?(tree_path))
      end

      ndetails = 5
      tree = MultiTree.new(tree_path,ndetails)

      if pass == 0
        ps1 = prepare_tree(tree)
        tree.close
      else
        w = prepare_ws("../multi_tree.ps")

        steps = 4
        (ndetails*steps).times do |i|
          dt = i/steps
          w.new_page("MultiTree detail=#{dt}")

          r = Bounds.new(10+i*16,190+i*10,700,600)

          pts = tree.find(r,dt)

          w.push(w.set_gray(0))
          w.draw_rect(r.x,r.y,r.w,r.h  )
          w.pop

          if !bgnd
            w.start_buffer
            plot_pts(w,ps1,0.8)
            bgnd = w.stop_buffer
            w.add_element('bgnd',bgnd)
          end
          w.draw_element('bgnd')

          w.push(w.set_rgb(0.75,0,0))
          plot_pts_colored(w,pts,1.2)
          w.pop

        end
        w.close();
      end
    end
  end

end

