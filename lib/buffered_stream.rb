#--
# Copyright 2009 Ryan Blue.
# Distributed under the terms of the GNU General Public License (GPL).
# See the LICENSE file for further information on the GPL.
#++

class ProtoStruct
  # this class is intended to extend IO objects for sending/receiving
  # ProtoStruct-derived messages.  this clas is modeled after
  # Net::SSH::BufferedIo(http://rubyforge.org/projects/net-ssh) by
  # Jamis Buck
  #
  # intended usage:
  #  class Message < ProtoStruct
  #    length :l, 8.bits
  #    string :str, :length_field => :l
  #  end
  #
  #  s = TCPSocket.new(...)
  #  s.extend(ProtoTools::BufferedStream)
  #
  #  read_set, write_set = select([s], s.pending_write? ? [s] : nil, nil, 0.1)
  #  if read_set && read_set.member? s
  #    s.fill
  #  end
  #
  #  if s.available
  #    s.parse_available( Message ) { |m|
  #      puts m.str
  #    }
  #  end
  #
  #  if write_set && write_set.member? s
  #    s.send_pending
  #  end
  module BufferedStream
    def self.extended( o )
      o.__send__ :init_buffered_stream
    end

    attr_reader :in_buffer
    attr_reader :out_buffer

    # sets the maximum output rate for the stream
    #
    # undestands bits, bytes, and fixnums.  out_rate = nil will remove rate
    # limiting.
    #
    # returns the output rate in bytes per second.
    def out_rate=( per_second )
      return @out_rate = per_second                if per_second.nil?
      return @out_rate = per_second                if per_second.is_a? Bytes
      return @out_rate = per_second.to_bytes       if per_second.is_a? Bits
      return @out_rate = per_second.bits.to_bytes  if per_second.is_a? Fixnum
      raise ArgumentError, "rate must be a number or nil (reset)"
    end

    def <<( msg )
      if msg.is_a? String
        @out_buffer << msg
      elsif msg.is_a? ProtoStruct
        @out_buffer << msg.to_wire
      else
        @out_buffer << msg.to_s
      end
      self
    end

    # returns true if there are pending bytes to send
    def pending_write?
      return @out_buffer.length > 0
    end

    # returns the number of pending bytes to be sent
    def pending
      return @out_buffer.length
    end

    # sends pending bytes (will block)
    # 
    # respects rate_limit
    def send_pending
      l = write( @out_buffer )
      consume!( @out_buffer, l )
    end

    # sends pending bytes (will not block)
    # 
    # respects rate_limit
    def send_pending_nonblock
      l = write_nonblock( @out_buffer )
      consume!( @out_buffer, l )
    end

    # fills the input buffer (will block)
    def fill( n = 8192 )
      data = read( n )
      @in_buffer << data
      return data.length
    end

    # fills the input buffer (will not block)
    def fill_nonblock( n = 8192 )
      data = read_nonblock( n )
      @in_buffer << data
      return data.length
    end

    # returns the length of the input buffer
    def available
      return @in_buffer.length
    end

    # yields all messages of class +c+ from the in buffer
    def get_available( c, &blk )
      c.parse_stream( @in_buffer, &blk )
    end

    # attempts to yiedl one message of class +c+ from the in buffer
    def get_next( c, &blk )
      c.parse_msg( @in_buffer, &blk )
    end

  private

    def consume!( buf, num )
      buf.slice!( 0..(num-1) )
    end

    def init_buffered_stream
      @in_buffer = String.new
      @out_buffer = String.new
      @out_rate = nil
    end

  end # of class BufferedStream
end # of class ProtoStruct
