# Bits 'n' Bytes - unit additions to the Integers
#--
# Copyright 2009 Ryan Blue.
# Distributed under the terms of the GNU General Public License (GPL).
# See the LICENSE file for further information on the GPL.
#++
#
# A couple of simple classes and extensions to Integer to allow using .bytes
# and .bits to specify units.  This makes your bit/byte conversions simpler and
# more readable:
#
#  >> def valid_size?( size )
#  >>   case size
#  >>     when 32.bits
#  >>       true
#  >>     when 16.bits
#  >>       true
#  >>     when 8.bits
#  >>       true
#  >>     else
#  >>       false
#  >>   end
#  >> end
#  >> valid_size? 4.bytes
#  => true
#  >> valid_size? 16.bits
#  => true
#  >> valid_size? 8
#  => true
#
# Note: values without units are assumed to be in bits

class Bytes # :nodoc
  include Comparable

  def initialize( num )
    @i = num.to_i
  end

  def to_i
    @i
  end

  def inspect
    to_s
  end

  #convert from Bytes to Bits
  def to_bits
    Bits.new( @i << 3 )
  end
  alias bits to_bits

  def to_bytes
    self
  end
  alias bytes to_bytes

  def +( b )
    return (@i + b.to_i).bytes if b.is_a? Bytes
    (( @i << 3 ) + b.to_i).bits
  end

  def -( b )
    return (@i - b.to_i).bytes if b.is_a? Bytes
    (( @i << 3 ) - b.to_i).bits
  end

  def <=>( b )
    return (( @i << 3 ) <=> b.to_i) if b.is_a? Bits
    (@i <=> b.to_i)
  end

  def to_s
    "#{@i} byte" + ( @i == 1 ? '' : 's' )
  end
end

class Bits # :nodoc
  include Comparable

  def initialize( num )
    @i = num.to_i
  end

  def to_i
    @i
  end

  def inspect
    to_s
  end

  def to_bits
    self
  end
  alias bits to_bits

  # convert from Bits to Bytes
  def to_bytes
    Bytes.new( @i >> 3 )
  end
  alias bytes to_bytes

  def +( b )
    return (@i + ( b.to_i << 3 )).bits if b.is_a? Bytes
    (@i + b.to_i).bits
  end

  def -( b )
    return (@i - ( b.to_i << 3 )).bits if b.is_a? Bytes
    ( @i - b.to_i).bits
  end

  def <=>( b )
    return (@i <=> ( b.to_i << 3 )) if b.is_a? Bytes
    (@i <=> b.to_i)
  end

  def to_s
    "#{@i} bit" + ( @i == 1 ? '' : 's' )
  end
end

class Integer
  # adds Bytes unit
  def bytes
    Bytes.new( self )
  end

  # adds Bits unit
  def bits
    Bits.new( self )
  end
end
