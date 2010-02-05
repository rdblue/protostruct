require 'pp'
require 'lib/protostruct'

module Consts
  ONE = 0x01
  TWO = 0x02
  THREE = 0x03
end

class Message < ProtoStruct
  length :msg_size, 4.bytes, :included => false
  octets :chunk, :length_field => :msg_size
end

class Embed1 < ProtoStruct
  uint32 :int
end

class Embed2 < ProtoStruct
  uint16 :short
end

class Embed3 < ProtoStruct
  uint8 :byte
end

class Test < ProtoStruct
  enum   :code, 8.bits, Consts.name_hash
  embed  :body, :code, {
      :ONE => Embed1,
      :TWO => Embed2
    }
end

t = Test.new(:code => :ONE, :int => 34)

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
  length :msg_size, 4.bytes, :for => [:opcode, :body]
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

'string'.to_hexdump
