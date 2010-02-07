# BitTorrent::Protocol::Mainline
#--
# Copyright 2009 Ryan Blue.
# Distributed under the terms of the GNU General Public License (GPL).
# See the LICENSE file for further information on the GPL.
#++
#
# for more information on bittorrent mainline protocol, see:
# * http://bittorrent.org/beps/bep_0004.html
# * http://wiki.theory.org/BitTorrentSpecification
#

require 'rubygems'
require 'protostruct'

module BitTorrent # :nodoc
  module Protocol # :nodoc
    # MainLine implements the standard bittorrent protocol, without message
    # extensions and is agnostic to those extensions (reserved_bytes are all
    # null)
    module MainLine
      # enum of the mainline protocol's opcodes
      module OpCodes
        CHOKE           = 0x00
        UNCHOKE         = 0x01
        INTERESTED      = 0x02
        UNINTERESTED    = 0x03
        HAVE            = 0x04
        BITFIELD        = 0x05
        REQUEST         = 0x06
        PIECE           = 0x07
        CANCEL          = 0x08
      end

      module Constants
        HANDSHAKE = "\x13BitTorrent protocol"
      end

      # the initial protocol message
      class HandShake < ProtoStruct
        string :proto_str, :size => 20.bytes
        octets :reserved, :size => 8.bytes
        octets :info_hash, :size => 20.bytes
        octets :peer_id, :size => 20.bytes

        def initialize( options = {} )
          super( {
              :proto_str => Constants::HANDSHAKE,
              :reserved => ( "\0" * 8 )
            }.merge( options ) )
        end
      end

      class Have < ProtoStruct
        uint32 :index
      end

      class BitField < ProtoStruct
        string :bitfield
      end

      class Request < ProtoStruct
        uint32 :index
        uint32 :offset
        uint32 :chunk_size
      end

      class Piece < ProtoStruct
        uint32 :index
        uint32 :offset
        octets :chunk
      end

      # default message from which wraps the other protocol messages (other
      # than HandShake or KeepAlive)
      class MainMessage < ProtoStruct
        enum :opcode, 8.bits, OpCodes.name_hash
        embed :body, :opcode, {
            :HAVE => Have,
            :BITFIELD => BitField,
            :REQUEST => Request,
            :PIECE => Piece,
            :CANCEL => Request # use request - has the same payload
            # opcodes not listed here have no payload (nil)
          }
      end

      # this probably warrants an update to ProtoStruct, where you can declare
      # an alternate creator method that is automatically aliased to new unless
      # it is overloaded
      class Message < ProtoStruct
        length :msg_size, 4.bytes, :included => false
        embed  :body, :msg_size, {
            0 => nil
          }.with_default( MainMessage ),
          { :length_field => :msg_size }

        def self.keepalive
          new( :msg_size => 0 )
        end

        def keepalive?
          ( msg_size == 0 )
        end

        def initialize( options = {} )
          super( {
              :msg_size => 1 # make sure it has a body
            }.merge( options ) )
        end
      end
    end # of class MainLine
  end # of class Protocol
end # of class BTorrent
