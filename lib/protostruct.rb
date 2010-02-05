# ProtoStruct
#--
# Copyright 2009 Ryan Blue.
# Distributed under the terms of the GNU General Public License (GPL).
# See the LICENSE file for further information on the GPL.
#++
#
#--
# TODO
# * add support for specific delimiters (like ;; or CRLF): field_delimiter & msg_delimiter
# * raise exceptions when we catch definition problems
# * support direct embedding
# * support inflate/deflate options on lengths
# * allow lengths to be used for embedding keys
# * add :strict option to enums (kind accepting, unkind accepting)
# * add support for conditional fields (:required, :optional, :condition => [:version, '> 3'])
#++

###-- required libraries ++#####################################################

require 'rubygems'

begin
  require 'units'
rescue LoadError
  $:.push File.dirname(__FILE__)
  require 'units'
end

require 'buffered_stream'

###-- hack on the String class to add hexdump -C support ++#####################

class String # :nodoc all
  def to_hexdump
    out = ''
    bytes = nil
    printable = nil

    self.split(//).each_with_index do |b, count|
      if count % 0x10 == 0
        out << ( "%-49s |%s|\n" % [bytes, printable] ) if bytes
        bytes = ''
        printable = ''
        out << ( "%08X  " % count )
      elsif count % 0x08 == 0
        bytes << ' '
        printable << ' '
      end

      bytes << "#{b.unpack('H*').first} "

      i = b.unpack('c').first
      printable << ( ( ( i >= 0x20 ) && ( i <= 0x7E ) ) ? b : '.' )
    end

    out << ( "%-49s |%s|\n" % [bytes, printable] ) unless bytes.nil? || bytes.empty?
  end
end

###-- hack on the Symbol class to easily change symbols ++######################

class Symbol # :nodoc all
  def +( s )
    (self.to_s + s.to_s).to_sym
  end
end

###-- hack on the Hash class to allow in-declaration defaults ++################

class Hash # :nodoc all
  def with_default( val )
    self.default = val
    self
  end
end

###-- hack on the Module class to easily access constants ++####################

class Module # :nodoc all
  def name_hash
    @name_hash ||= constants.inject({}) do |h, k|
      h.merge( {k.to_sym => const_get(k)} )
    end
  end

  def value_hash
    @value_hash ||= constants.inject({}) do |h, k|
      h.merge( {const_get(k) => k.to_sym} )
    end
  end
end

###-- ProtoStruct class definition ++###########################################

# ProtoStruct provides a simple way to define protocol objects
#
# Protocol objects can be declared using field methods to control the structure.  Example:
#
#  class UDP < ProtoStruct
#    uint16 :source_port
#    uint16 :dest_port
#    length :udp_len, 16.bits
#    uint16 :checksum
#    string :data
#  end
#
#  bytes = sock.read
#  packet = UDP.parse( bytes )
#
#  outgoing = UDP.new
#  outgoing.source_port = 3434
#  outgoing.dest_port = 4343
#  outgoing.data = "my data"
#  sock.write( packet.to_wire )
#
# Available field methods are:
# * uint64
# * sint64 (also: int64)
# * uint32
# * sint32 (also: int32)
# * uint16
# * sint16 (also: int16)
# * uint8
# * sint8 (also: int8)
# * length
# * enum
# * octets (also: string, bytes)
# * embed (also: nested)
#
# Field methods declare accessor methods for fields, so <tt>uint32 :index</tt>
# will create methods <tt>index</tt> and <tt>index=</tt>.
#
# Class methods inherited by ProtoStruct objects:
# * parse_msg
# * parse_stream
#
# Instance methods inherited by ProtoStruct objects:
# * to_wire
# * length (also: size)
class ProtoStruct
  ###-- FieldTypes module definition ++#########################################
  module FieldTypes
    UINT64      = 1
    SINT64      = 2
    UINT32      = 3
    SINT32      = 4
    UINT16      = 5
    SINT16      = 6
    UINT8       = 7
    SINT8       = 8
    LENGTH      = 9
    ENUM        = 10
    OCTETS      = 11
    EMBED       = 12
  end # of FieldTypes

  ###-- Constants module definition ++##########################################
  module Constants
    BIG_ENDIAN    = true
    NETWORK       = true
    LITTLE_ENDIAN = false
  end # of Constants

  ###-- Error class definitions ++##############################################
  class ParseError < RuntimeError; end
  class DefinitionError < SyntaxError; end
  class IncompleteMessage < RuntimeError; end

  ###-- SymbolTable class definition ++#########################################
  # Keeps track of mappings between ProtoStruct object attributes and wire
  # representations
  class SymbolTable
    include Enumerable

    def initialize
      @tab = []
      @name_to_index = {}
    end

    # Returns the index in the table with <tt>:name</tt> equal to +sym+
    def lookup( sym )
      return @name_to_index[sym]
    end

    # Returns true if there exists a table entry with <tt>:name</tt> equal to
    # +sym+
    def include?( sym )
      return @name_to_index.key?( sym )
    end

    # Returns the appropriate symbol table entry
    #
    # Parameters:
    # +o+ (+Integer+) :: returns the o'th table entry
    # +o+ (+Symbol+) :: returns the table entry with name o
    def []( o )
      return @tab[o]            if o.is_a? Integer
      ind = lookup( o )         if o.is_a? Symbol
      ind = lookup( o.to_sym )  if o.is_a? String
      return @tab[ ind ]        unless ind.nil?
      return nil
    end

    # Adds an entry to the symbol table
    #
    # Entries are Hash objects that contain _at_ _least_ the following fields:
    # <tt>:name</tt> :: a Symbol name for the entry
    # <tt>:type</tt> :: the type of entry (from ProtoStruct::FieldTypes)
    def add( s )
      # verify
      raise ArgumentError unless s[:name]
      raise ArgumentError unless s[:type]

      # do the addition
      @name_to_index[s[:name]] = @tab.size
      @tab << s
    end
    alias << add

    # Method to *replace* the map for a given symbol
    def set_map( sym, map )
      raise ArgumentError unless map.is_a? Hash

      ind = @name_to_index[ sym ]
      raise ArgumentError unless ind

      @tab[ind][:map] = map
    end

    # Method to *alter* the map for a given symbol
    def merge_map( sym, map )
      raise ArgumentError unless map.is_a? Hash

      ind = @name_to_index[ sym ]
      raise ArgumentError unless ind

      @tab[ind][:map].merge!( map )
    end

    # An enumerator that yields each table entry in the order they are declared
    #
    # Returns an Array of all entries if no block is given
    def each( type = nil ) # :yields: entry
      @tab.each do |s|
        next if type and s[:type] != type
        yield s
      end
    end

    # Returns an Array of all entries
    def all
      return @tab
    end

    # Returns a String containing a human-readable description of the table
    def describe
      ret  = "Name             Type     Size\n"
      ret << "================ ======== ========\n"
      @tab.each do |s|
        ret << "%-16s %-8s %s\n" % [ s[:name],
            FieldTypes.value_hash[ s[:type] ], s[:size] || 'variable' ]
      end
      ret
    end
  end # of class SymbolTable

  ###-- ProtoStruct class methods ++############################################
  # these can be called from any subclass of ProtoStruct
  class << self

    ###-- Field definition methods ++###########################################

    # make sure everything is set up and ready to go, no matter which
    # declaration method is used first
    def ensure_setup
      @symtab ||= SymbolTable.new
      @unpacker ||= ''
      @packer ||= ''
      @static ||= 0.bits
    end

    # declare an 8-byte unsigned integer
    def uint64( name, options = {} )
      ensure_setup

      @symtab << { :name => name, :size => 64.bits, :type => FieldTypes::UINT64 }
      @unpacker << 'Q'
      @packer << 'Q'

      attr_accessor name
    end

    # declare an 8-byte signed integer
    def sint64( name, options = {} )
      ensure_setup

      @symtab << { :name => name, :size => 64.bits, :type => FieldTypes::SINT64 }
      @unpacker << 'q'
      @packer << 'q'

      attr_accessor name
    end

    # declare a 4-byte unsigned integer
    #
    # options:
    # <tt>:endian</tt> :: set to <tt>:little</tt> to force little endian
    def uint32( name, options = {} )
      ensure_setup

      big_endian = (options[:endian] != :little)

      @symtab << { :name => name, :size => 32.bits, :type => FieldTypes::UINT32 }
      @unpacker << ( big_endian ? 'N' : 'V' )
      @packer << ( big_endian ? 'N' : 'V' )

      attr_accessor name
    end

    # declare a 4-byte signed integer
    #
    # options:
    # <tt>:endian</tt> :: set to <tt>:little</tt> to force little endian
    def sint32( name, options = {} )
      fail Errno::ENOSYS
      ensure_setup

      big_endian = (options[:endian] != :little)

      @symtab << { :name => name, :size => 32.bits, :type => FieldTypes::SINT32 }
      @unpacker << ( big_endian ? '' : '' )
      @packer << ( big_endian ? '' : '' )

      attr_accessor name
    end
    alias int32 sint32

    # declare a 2-byte unsigned integer
    #
    # options:
    # <tt>:endian</tt> :: set to <tt>:little</tt> to force little endian
    def uint16( name, options = {} )
      ensure_setup

      big_endian = (options[:endian] != :little)

      @symtab << { :name => name, :size => 16.bits, :type => FieldTypes::UINT16 }
      @unpacker << ( big_endian ? 'n' : 'v' )
      @packer << ( big_endian ? 'n' : 'v' )

      attr_accessor name
    end

    # declare a 2-byte signed integer
    #
    # options:
    # <tt>:endian</tt> :: set to <tt>:little</tt> to force little endian
    def sint16( name, options = {} )
      fail Errno::ENOSYS
      ensure_setup

      big_endian = (options[:endian] != :little)

      @symtab << { :name => name, :size => 16.bits, :type => FieldTypes::SINT16 }
      @unpacker << ( big_endian ? '' : '' )
      @packer << ( big_endian ? '' : '' )

      attr_accessor name
    end
    alias int16 sint16

    # declare a 1-byte unsigned integer
    def uint8( name, options = {} )
      ensure_setup

      @symtab << { :name => name, :size => 8.bits, :type => FieldTypes::UINT8 }
      @unpacker << 'C'
      @packer << 'C'

      attr_accessor name
    end

    # declare a 1-byte signed integer
    def sint8( name, options = {} )
      ensure_setup

      @symtab << { :name => name, :size => 8.bits, :type => FieldTypes::SINT8 }
      @unpacker << 'c'
      @packer << 'c'

      attr_accessor name
    end
    alias int8 sint8

    # declare a length field
    #
    # used to determine message boundaries when parsing raw octet streams and
    # embedded messages; set automatically in to_wire
    #
    # *parameters*:
    #
    # <tt>name</tt> :: symbol for accessor creation
    # <tt>size</tt> :: size to use for encoding (must be 1, 2, or 4 bytes)
    #
    # *options*:
    #
    # <tt>:for</tt> :: field Symbol(s) included in this length
    # <tt>:included</tt> :: true or false; whether to include this field
    # <tt>:endian</tt> :: set to <tt>:little</tt> to force little endian
    def length( name, size, options = {} )
      ensure_setup

      big_endian = (options[:endian] != :little)
      size = size.bits # ensure it has units

      h = {
          :name => name,
          :size => size,
          :for => ( options[:for] ? [ options[:for] ].flatten : nil ),
          :included => options[:included],
          :static => ( options[:included] ? size : 0.bits ),
          :dynamic => [],
          :type => FieldTypes::LENGTH
        }

      # run over the already declared fields and update lengths
      fields = h[:for]
      @symtab.each do |s|
        next unless fields.nil? || fields.include?( s[:name] )
        if s[:size]
          h[:static] += s[:size]
        else
          s[:dynamic] << s[:name]
        end
      end

      # note that all pack/unpack symbols are unsigned (as are lengths)
      case size
        when 32.bits
          @symtab << h
          @unpacker << ( big_endian ? 'N' : 'V' )
          @packer << ( big_endian ? 'N' : 'V' )
        when 16.bits
          @symtab << h
          @unpacker << ( big_endian ? 'n' : 'v' )
          @packer << ( big_endian ? 'n' : 'v' )
        when 8.bits
          @symtab << h
          @unpacker << 'C'
          @packer << 'C'
        else
          raise ArgumentError, 'Size must be 8, 16, or 32 bits'
      end

      attr_accessor name
    end

    # declare an enumerated field
    #
    # *parameters*:
    #
    # <tt>name</tt> :: symbol for accessor creation
    # <tt>map</tt> :: a hash mapping Symbols to wire representations (Integers)
    # <tt>size</tt> :: size to use for encoding (must be 1, 2, or 4 bytes)
    #
    # *options*:
    #
    #
    def enum( name, size, map, options = {} )
      ensure_setup

      h = { :name => name, :map => map, :size => size, :type => FieldTypes::ENUM }

      case size
        when 32.bits
          @symtab << h
          @unpacker << ( big_endian ? 'N' : 'V' )
          @packer << ( big_endian ? 'N' : 'V' )
        when 16.bits
          @symtab << h
          @unpacker << ( big_endian ? 'n' : 'v' )
          @packer << ( big_endian ? 'n' : 'v' )
        when 8.bits
          @symtab << h
          @unpacker << 'C'
          @packer << 'C'
        else
          raise ArgumentError, 'Size must be 8, 16, or 32 bytes'
      end

      attr_accessor name
    end

    # declare a field of raw bytes
    #
    # *parameters*:
    #
    # <tt>name</tt> :: symbol for accessor creation
    #
    # *options*
    #
    # <tt>:size</tt> :: indicates a fixed size for the embedded field
    # <tt>:length_field</tt> :: field to set/query in length calculations
    #
    # <tt>:size</tt> takes precedence over <tt>:length_field</tt>
    def octets( name, options = {} )
      ensure_setup

      h = { :name => name, :type => FieldTypes::OCTETS }

      if l = options[:size]
        @symtab << h.merge( { :size => l } )
        @unpacker << "a#{l.to_i}"
        @packer << "a#{l.to_i}"
      else
        if sym = options[:length_field]
          @symtab << h.merge( { :length => sym } )
          @unpacker << ':a%u'
        else
          @symtab << h
          @unpacker << 'a*'
        end
        @packer << 'a*'
      end

      attr_accessor name
    end
    alias bytes octets
    alias string octets

    # declare an embedded field
    #
    # *parameters*:
    #
    # <tt>name</tt> :: symbol for accessor creation
    # <tt>key</tt> :: field to use in determining the type of embedded object
    # <tt>map</tt> :: mapping between +key+ values and Classes
    #
    # Typically, the +key+ field should be a previously-declared +enum+ field
    #
    # *options*
    #
    # <tt>:size</tt> :: indicates a fixed size for the embedded field
    # <tt>:length_field</tt> :: field to set/query in length calculations
    # <tt>:size</tt> takes precedence over <tt>:length_field</tt>
    #
    # *embedding*
    #
    # Any class can be embedded, so long as it defines the following methods:
    # <tt>to_wire</tt> :: returns a wire representation that parse can handle
    # <tt>length</tt> :: returns the size of the serialized version
    # <tt>self.parse_msg</tt> :: returns an instance from the wire version
    # All subclasses of ProtoStruct meet these requirements.
    def embed( name, key, map, options = {} )
      ensure_setup

      h = { :name => name, :key => key, :map => map, :type => FieldTypes::EMBED }

      # verify the key field to make sure parsing will succeed
      s = @symtab[key]
      raise( DefinitionError, "embedded field key :#{key} is not defined" ) if s.nil?

      if l = options[:size]
        @symtab << h.merge( { :size => l } )
        @unpacker << "a#{l.to_i}"
        @packer << "a#{l.to_i}"
      else
        if sym = options[:length_field]
          @symtab << h.merge( { :length => sym } )
          @unpacker << ':a%u'
        else
          @symtab << h
          @unpacker << 'a*'
        end
        @packer << 'a*'
      end

      attr_accessor name
    end
    alias nested embed

    ###-- Object access access methods ++#######################################

    # returns a String containing a human-readable description of the class's
    # SymbolTable.
    def describe
      @symtab.describe
    end

    # Returns the class's _staged_ unpack string
    #
    # <b>Staged unpack strings</b>
    #
    # Staged unpack strings are _not_ ready to be used in calls to
    # String#unpack.  Staged unpack strings are unpack strings that require
    # multiple unpack calls because lengths are not known, but are discovered
    # during the unpack process.  An example is length-prefixed strings:
    #
    #   "\x13BitTorrent protocol'
    #   "\x06string'
    #
    # Declared in ProtoStruct as:
    #
    #   class PString < ProtoStruct
    #     length :len, 1.byte, :for => :s
    #     string :s, :length_field => :len
    #   end
    #   PString.unpacker
    #   => 'C:a%s'
    #
    # *Format*
    #
    # Staged unpack strings contain two additions to the String#unpack format:
    # <tt>:</tt> :: delimits unpack stages
    # <tt>%u</tt> :: place-holder for length information
    #
    # Note: Staged unpack strings may be used in calls to unpack if no ':'
    # delimiters are found, however, the ProtoStruct.parse* functions do all
    # the unpacking for you.
    def unpacker
      @unpacker
    end

    # Returns the class's pack string.
    #
    # This string is ready to be used in Array#pack, however this is done for
    # you by ProtoStruct#to_wire
    def packer
      @packer
    end

    # Returns the class's symbol table.
    def symbol_table
      @symtab
    end

    # Parses the raw input bytes using the message's staged unpack string
    #
    # *parameters*
    #
    # <tt>raw</tt> :: a buffer of raw bytes to parse into objects
    #
    # *raises*
    #
    # * IncompleteMessage if there are not enough bytes to parse a message
    def parse_msg( raw )
      this = new

      buffer = raw.dup  # don't clobber in case there aren't enough bytes to
                        # unpack the whole thing!
      num_bytes = buffer.length.bytes
      used_bytes = 0.bytes
      needed_bytes = @static

      i = 0 # current index in to the symbol table and...
      s = @symtab[i] # an alias for the current entry

      stages = @unpacker.split /:/
      stages.each do |stage|
        # prepare the stage - make the length concrete
        # we know that s (= @symtab[i]) is what needs the length
        if i > 0
          clen = concrete_length( s, this ).to_bytes.to_i
          stage = stage % [ clen ]
          needed_bytes += clen.bytes
        end

        # puts "num_bytes = #{num_bytes}, needed_bytes = #{needed_bytes}\n"
        raise IncompleteMessage if ( num_bytes - needed_bytes < 0 )

        # grab this stage and set the buffer to the rest
        l = buffer.length
        a = buffer.unpack( stage + 'a*' )
        #puts "unpack(#{stage}) => [#{a.join(', ')}]"
        buffer = a.pop

        l -= buffer.length
        used_bytes += l.bytes

        # set the unpacked values in +this+
        a.each do |value|
          set_sym = s[:name] + '='

          case s[:type]
            when FieldTypes::EMBED
              k = this.send s[:key]
              klass = s[:map][k]
              # if we don't need to instantiate, don't
              unless ( klass.nil? || value.empty? )
                this.send( set_sym, klass.parse_msg( value ) )
              end

            when FieldTypes::ENUM
              this.send set_sym, s[:map].invert[value]

            else
              # the simple one - set the value
              this.send set_sym, value
          end

          i += 1 # advance to the next entry in the symbol table
          s = @symtab[i] # alias the symbol table entry
        end

      end # end each stage

      # successful parsed the full message => side-effect the raw bytes
      consume!( raw, used_bytes.to_bytes.to_i )

      if block_given?
        yield this
      end

      return this
    end

    # side-effects raw
    def parse_stream( raw, &blk )
      acc = Array.new
      while true
        acc << parse_msg( raw, &blk )
      end
    rescue IncompleteMessage
      return acc
    end

  private

    def consume!( str, num )
      str.slice!( 0..(num-1) )
    end

    # this is run after every method is added to this class.  this method
    # maintains consistency on length fields.  static lengths (for instance,
    # from declaring a uint32) are accumulated in :static for any length fields
    # that include the symbol.  dynamic lengths (for instance, declaring a
    # string without a :static_length option) are tracked by field symbol in
    # :dynamic for the appropriate length fields.
    def method_added( name )
      # grab the entry in the symbol table if it exists
      return unless @symtab
      n = @symtab[name]
      return unless n

      @static += n[:size] if n[:size]

      return if n[:type] == FieldTypes::LENGTH

      if n[:length]
        # update the corresponding length field
        s = @symtab[ n[:length] ]
        s[:dynamic] << name

      else
        @symtab.each( FieldTypes::LENGTH ) do |s|
          next if ( s[:for] && !s[:for].include?( name ) )
          if n[:size]
            s[:static] += n[:size]
          else
            s[:dynamic] << name
          end
        end
      end

      return
    end

    # calculates the concrete length of a dynamic field from its length
    # field
    def concrete_length( s, this )
      # get the symbol table entry for the field's length parameter
      l = @symtab[s[:length]]

      # return the actual length parsed - the size of any static fields
      return ( this.send( l[:name] ).bytes - l[:static] )
    end

  end # of metaclass definitions

  # create a new ProtoStruct-derived object
  #
  # *options*
  #
  #
  def initialize( options = {} )
    self.class.symbol_table.each do |s|
      set_sym = s[:name] + '='

      if options.key? s[:name]
        self.send set_sym, options[s[:name]]

      elsif ( s[:type] == FieldTypes::EMBED ) && ( options.key? s[:key] )
        key = options[s[:key]]
        klass = s[:map][key]
        self.send set_sym, klass.new( options ) unless klass.nil?
      end
    end
  end

  # calculate the total message length (required for embedding)
  def length
    self.class.symbol_table.inject(0.bits) do |sum, s|
      if s[:size]
        sum += s[:size]
      else
        t = self.send( s[:name] )
        sum += ( t ? t.length.bytes : 0.bytes )
      end
    end
  end
  alias size length

  # converts the object to its wire representation
  def to_wire
    arr = self.class.symbol_table.collect do |s|
      case s[:type]
        when FieldTypes::LENGTH
          # calculate the final length to use
          l = s[:static]
          s[:dynamic].each do |sym|
            t = self.send( sym )
            l += ( t ? t.length.bytes : 0.bytes )
          end
          l.to_bytes.to_i

        when FieldTypes::ENUM
          # use the representation
          s[:map][self.send( s[:name] )]

        when FieldTypes::EMBED
          # embed the wire representation of the class
          t = self.send( s[:name] )
          t ? t.to_wire : nil

        else
          # just get the value
          self.send s[:name]
      end
    end

    #puts "[#{arr.join(', ')}].pack(#{self.class.packer})"
    arr.pack(self.class.packer)
  end

  # see if any embedded objects can handle the request
  def method_missing( sym, *args )
    self.class.symbol_table.each( FieldTypes::EMBED ) do |s|
      child = self.send( s[:name] )
      next unless child

      return child.send( sym, *args ) if child.respond_to? sym
    end

    self.class.symbol_table.each( FieldTypes::EMBED ) do |s|
      child = self.send( s[:name] )
      next unless child

      begin
        return child.send( sym, *args )
      rescue NoMethodError
      end
    end

    raise NoMethodError, "#{sym} not found"
  end

end # of class ProtoStruct
