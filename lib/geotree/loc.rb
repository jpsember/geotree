module GeoTreeModule

  LOC_MAX = ((1 << 30)-1)
  LOC_MIN = -LOC_MAX

  # Factor for converting integer locations to latitude/longitudes
  LAT_LONG_FACTOR_ = 180.0 / LOC_MAX

  # Represents an x,y location.
  # Each coordinate is stored internally as an integer, but may be
  # referred to as a latitude and longitude as well.
  #
  class Loc

    attr_accessor :x,:y

    def self.cvt_latlong_to_int(n)
      m = (n / LAT_LONG_FACTOR_ + 0.5).to_i
      raise ArgumentError,"Converting lat/long #{n} is out of range" if m < LOC_MIN || m > LOC_MAX
      m
    end

    # Construct a point.
    # If x is a Float, it assumes that x and y are
    # longitude and latitude respectively, and converts them
    # to integer values.
    #
    def initialize(x = 0, y = 0)
      if x.is_a? Float
        x = Loc.cvt_latlong_to_int(x)
        y = Loc.cvt_latlong_to_int(y)
      end
      @x = x
      @y = y
    end

    # Get x as a longitudinal coordinate
    #
    def longit
      @x * LAT_LONG_FACTOR_
    end

    # Get y as a latitudinal coordinate
    #
    def latit
      @y * LAT_LONG_FACTOR_
    end

    def to_s
      "(#{x},#{y})"
    end

    def inspect
      to_s
    end

    def set_to(src)
      @x = src.x
      @y = src.y
    end

    # Return a version of the point with the coordinates exchanged
    #
    def flip
      Loc.new(@y,@x)
    end
  end
end
