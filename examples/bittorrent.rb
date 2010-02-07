# BitTorrent::Protocol
#--
# Copyright 2009 Ryan Blue.
# Distributed under the terms of the GNU General Public License (GPL).
# See the LICENSE file for further information on the GPL.
#++

require 'rubygems'
require 'protostruct'
require 'bittorrent/mainline'
require 'bittorrent/ltep'

module BitTorrent # :nodoc
	module Defaults
		PORT				= 6881
		PEER_ID			= "RB-0-1-0        %04u" % rand(9999)
		CHUNK_SIZE	= 2**14	# known to work with AZ, TR
	end

  # The protocol module contains all of the necessary
  # serialization/deserialization routines necessary to communicate with other
  # bittorrent clients.  Serialization is done either by instantiating Protocol
  # messages and calling their to_s functions, or by calling Protocol class
  # methods.  Deserialization is done by successive calls to Protocol.parse( ),
  # which returns an array of Protocol::Message objects.
  module Protocol
    # this class is intended to extend IO objects for sending/receiving
    # bittorrent messages.  it is based on ProtoStruct::BufferedStream
    module Stream
      include ProtoStruct::BufferedStream

      attr_accessor :meta

      def self.extended( o )
        o.__send__ :init_buffered_stream
      end

      def send_handshake( peer_id = Defaults::PEER_ID )
        raise "meta data (.torrent) required before handshake can be sent" if meta.nil?
        h = MainLine::HandShake.new(
            :info_hash => meta.info_hash,
            :peer_id => ("%20s" % peer_id)
          )

        if block_given?
          yield h
        end

        self << h
      end

      def send_keepalive
        self << MainLine::Message.keepalive
      end

      def read_handshake( &blk )
        get_next( MainLine::HandShake, &blk )
      end

      def incoming( &blk )
        get_available( MainLine::Message, &blk )
      end

    end # of module Stream
  end # of module Protocol
end # of module BitTorrent
