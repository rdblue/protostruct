#!/usr/bin/env ruby
#--
# Copyright 2009 Ryan Blue.
# Distributed under the terms of the GNU General Public License (GPL).
# See the LICENSE file for further information on the GPL.
#++
#
# unit tests for ProtoStruct

require 'test/unit'
require 'protostruct'
require 'pp'

# some of these test classes are loosely based on bittorrent

class Request < ProtoStruct
  uint32 :index
  uint32 :offset
  uint32 :chunk_size

  def initialize( options = {} )
    super( {
        :index => 0,
        :offset => 0,
        :chunk_size => 0
      }.merge( options ) )
  end
end

class Chunk < ProtoStruct
  uint32 :index
  uint32 :offset
  octets :chunk

  def initialize( options = {} )
    super( {
        :index => 0,
        :offset => 0
      }.merge( options ) )
  end
end

class MyProto < ProtoStruct
  length :msg_size, 4.bytes
  enum :opcode, 8.bits, {
      :one => 0x01,
      :two => 0x02,
      :three => 0x03
    }
  nested :body, :opcode, {
      :one => Request,
      :two => Chunk,
      :three => nil # nothing embedded for this one
    }, {
      :length_field => :msg_size
    }

  def initialize( options = {} )
    super( {
        :opcode => :three
      }.merge( options ) )
  end
end

class ProtoStructTests < Test::Unit::TestCase
  def setup
    @r = Request.new( :index => 3, :offset => 1024, :chunk_size => 2**14 )
    @c = Chunk.new( :index => 4, :offset => 2048, :chunk => 'variable length string' )
    @mr = MyProto.new( :opcode => :one, :body => @r )
    @mc = MyProto.new( :opcode => :two, :body => @c )
  end

  def teardown
  end

  def remove_this_to_run_test_descriptions
    [Request, Chunk, MyProto].each do |c|
      puts c.name
      puts c.describe
      puts c.unpacker
      puts c.packer
      puts '='*40

      c.symbol_table.each( ProtoStruct::FieldTypes::LENGTH ) do |s|
        puts "length field #{s[:name]}: #{s[:static]} static"
      end
    end
  end

  def test_lengths
    assert_equal( @r.length, 12.bytes )
    assert_equal( @c.length, 30.bytes )
    assert_equal( @mr.length, 17.bytes )
    assert_equal( @mc.length, 35.bytes )
  end

  def test_parse_msg
    pr = Request.parse_msg( @r.to_wire )
    assert_equal( pr.to_wire, @r.to_wire )
    assert_equal( pr.index, @r.index )
    assert_equal( pr.offset, @r.offset )
    assert_equal( pr.chunk_size, @r.chunk_size )

    pc = Chunk.parse_msg( @c.to_wire )
    assert_equal( pc.to_wire, @c.to_wire )
    assert_equal( pc.index, @c.index )
    assert_equal( pc.offset, @c.offset )
    assert_equal( pc.chunk, @c.chunk )

    pm = MyProto.parse_msg( @mr.to_wire )
    assert_equal( pm.length, @mr.length )
    assert_equal( pm.opcode, @mr.opcode )
    assert_equal( pm.to_wire, @mr.to_wire )
    assert_equal( pm.body.class, @mr.body.class )
    assert_equal( pm.body.index, @mr.body.index )
    assert_equal( pm.body.offset, @mr.body.offset )
    assert_equal( pm.body.chunk_size, @mr.body.chunk_size )

    pm = MyProto.parse_msg( @mc.to_wire )
    assert_equal( pm.length, @mc.length )
    assert_equal( pm.opcode, @mc.opcode )
    assert_equal( pm.to_wire, @mc.to_wire )
    assert_equal( pm.body.class, @mc.body.class )
    assert_equal( pm.body.index, @mc.body.index )
    assert_equal( pm.body.offset, @mc.body.offset )
    assert_equal( pm.body.chunk, @mc.body.chunk )
  end

  def test_rand_stream
    # $stderr.puts srand( 14 )

    arr = Array.new

    assert_nothing_raised {
      1000.times do
        op = [:one, :two, :three][ rand(3) ]
        m = MyProto.new(
            :opcode => op,
            :index => rand(1024),
            :offset => rand(1024),
            :chunk_size => rand(1024),
            :chunk => rand.to_s
          )
        arr << m
      end

      wire_bytes = arr.inject('') { |w, m| w << m.to_wire }
      wire_bytes2 = ''
      arr.each do |m|
        wire_bytes2 += m.to_wire
      end
      assert_equal( wire_bytes, wire_bytes2 )

      m_old = nil
      MyProto.parse_stream( wire_bytes ) do |m_prime|
        m = arr.shift

        assert_equal( m.length, m_prime.length, "rand_stream: length does not match" )
        assert_equal( m.opcode, m_prime.opcode, "rand_stream: opcode does not match" )
        case m.opcode
        when :one
          assert_equal( m.index, m_prime.index, "rand_stream: index does not match" )
          assert_equal( m.offset, m_prime.offset, "rand_stream: offset does not match" )
          assert_equal( m.chunk_size, m_prime.chunk_size, "rand_stream: size does not match" )
        when :two
          assert_equal( m.index, m_prime.index, "rand_stream: index does not match" )
          assert_equal( m.offset, m_prime.offset, "rand_stream: offset does not match" )
          assert_equal( m.chunk, m_prime.chunk, "rand_stream: chunk does not match" )
        else
        end

        m_old = m
      end

      assert( arr.empty?, 'rand_stream did not parse enough messages' )
    }
  end
end
