# BTorrent::Protocol::LTEP
#--
# Copyright 2009 Ryan Blue.
# Distributed under the terms of the GNU General Public License (GPL).
# See the LICENSE file for further information on the GPL.
#++
#
# for more information on LibTorrent Extension Protocol (LTEP) see:
#	*	http://www.rasterbar.com/products/libtorrent/extension_protocol.html

###-- required libs ++##########################################################
require 'rubygems'
require 'protostruct'
require 'bcodec'
require 'bittorrent/mainline'

module BitTorrent # :nodoc
	module Protocol # :nodoc
		module LTEP
			module OpCodes
				EXTENDED	      = 0x14
			end

      module ExtStrings
        UT_PEX          = 'ut_pex'
      end

      module ExtCodes
        HANDSHAKE       = 0x00
        UT_PEX          = 0x01
      end

      class EmbedBCode
        def self.parse_msg( raw )
          this = new
          this.set( raw )
          return this
        end

        def initialize( options = {} )
        end

        def set( bstr )
          io = bstr                 if bstr.is_a? IO
          io = StringIO.new( bstr ) if bstr.is_a? String
          @storage = BCodec.decode( io )
        rescue => err
          STDERR.puts "Error decoding BEncoded payload: #{err}\n" +
                      "#{err.backtrace.join("\n")}\n" +
                      "#{bstr.to_hexdump}"
        end

        def to_wire
          BCodec.encode @storage
        end

        def length
          to_wire.length
        end
      end

      class HandShake < EmbedBCode
        def initialize( options = {} )
          # start off with the extensions defined in this file
          @storage = {
              'm' => ExtStrings.constants.inject({}) { |tab, c|
                  tab.merge( { ExtStrings.const_get( c ) =>
                                  ExtCodes.const_get( c ) } )
                },
              'p' => 6881,
              'v' => 'BTorrent' + ( BTorrent.version ? ' ' + BTorrent.version : '' )
            }

          [ :extensions, :port, :client ].each do |sym|
            set_sym = sym + '='
            self.send( set_sym, options[sym] ) if options.key? sym
          end
        end

        def extensions
          @storage['m']
        end

        def extensions=( h )
          raise ArgumentError unless h.is_a? Hash
          @storage['m'] = h
        end

        def port
          @storage['p']
        end

        def port=( p )
          raise ArgumentError unless p.is_a? Integer
          @storage['p'] = p
        end

        def client
          @storage['v']
        end

        def client=( v )
          raise ArgumentError unless v.is_a? String
          @storage['v'] = v
        end
      end

      class Peer < ProtoStruct
        # TODO: add custom initialization so :ip => '192.168.0.1', :port => 3434 works
        bytes  :raw_ip, :size => 4.bytes
        uint16 :port

        def ip
          IPv4.ctop( @raw_ip )
        rescue
          return ''
        end

        def ip=( str )
          @raw_ip = IPv4.ptoc( str )
        rescue
          raise ArgumentError,
            'argument must be an IPv4 address in dotted quad form'
        end
      end

      class PeerExchange < EmbedBCode
        def initialize( options = {} )
          @storage = {}
        end

        def added
          Peer.parse_stream( @storage['added'] )
        end

        def added=( *args )
          @storage['added'] ||= ''
          args.flatten.each do |p|
            next unless p.is_a? Peer
            @storage['added'] << p.to_wire
          end
          # allocate flags for those peers
          @storage['added.f'] = "\0" * args.length
        end

        def added_with_flags
          flags = @storage['added.f']
          ret = []
          added.each_with_index do |a, i|
            ret << [a, flags[i]]
          end
          ret
        end

        def dropped
          Peer.parse_stream( @storage['dropped'] )
        end

        def dropped=( *args )
          @storage['dropped'] ||= ''
          args.flatten.each do |p|
            next unless p.is_a? Peer
            @storage['dropped'] << p.to_wire
          end
        end
      end

      # message implementing the LT_Extension protocol
      class Extended < ProtoStruct
        enum :extcode, 8.bits, ExtCodes.name_hash
        embed :body, :extcode, {
            :HANDSHAKE => HandShake,
            :UT_PEX => PeerExchange
          }
        
        def self.add_pex_code( op )
          unless symbol_table[:extcode][:map].value? op # already defined?
            @num ||= 0
            @num += 1
            sym = :UT_PEX + @num
            symbol_table.merge_map( :extcode, { sym => op } )
            symbol_table.merge_map( :body, { sym => PeerExchange } )
          end
        end
      end
		end # of class LTEP

    ###-- Additions to MainLine classes ++#####################################
    module MainLine # :nodoc
      class MainMessage # :nodoc
        # Add new opcodes
        symbol_table.merge_map( :opcode, LTEP::OpCodes.name_hash )
        # and the embed mappings
        symbol_table.merge_map( :body, {
            :EXTENDED => LTEP::Extended
          } )
      end # of class Message

      class HandShake # :nodoc
        # set the LTEP bits in the BT HandShake
        def set_ltep
          return unless @reserved
          @reserved[5] |= 0x10
        end

        # check the LTEP bits in the BT HandShake
        def ltep?
          return false unless @reserved
          ( @reserved[5] & 0x10 ) != 0
        end
      end # of class HandShake
    end # of class MainLine
	end # of class Protocol
end # of class BitTorrent
