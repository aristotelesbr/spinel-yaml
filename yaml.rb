# yaml -- YAML.load / YAML.dump for Spinel, over the vendored libyaml 0.2.5.
#
# libyaml reads and writes the text (sp_yaml.c passes its events through
# as they are); this file turns parser events into Ruby values the way
# Psych does -- scalars typed by the YAML 1.1 rules, Hashes and Arrays,
# anchors and aliases, << merge keys, and the load / safe_load restrictions
# with Psych's exception classes and messages -- and Ruby values into
# emitter events with Psych's choice of style for each scalar. See
# README.md for what is not covered yet.

# Under CRuby (spin test's oracle, or a program run with plain `ruby`) this
# file shadows the stdlib's yaml.rb, so hand over to the real Psych. Spinel
# drops the branch before analysis.
unless RUBY_ENGINE == "spinel"
  require "psych"
  YAML = Psych
  return
end

module Psych
  VERSION = "5.3.1"
  LIBYAML_VERSION = "0.2.5"

  class Exception < ::RuntimeError
  end

  class BadAlias < Exception
  end

  class AliasesNotEnabled < BadAlias
    def initialize
      super("Alias parsing was not enabled. To enable it, pass `aliases: true` to `Psych::load` or `Psych::safe_load`.")
    end
  end

  class AnchorNotDefined < BadAlias
    def initialize(anchor_name)
      super("An alias referenced an unknown anchor: #{anchor_name}")
    end
  end

  class DisallowedClass < Exception
    def initialize(action, klass_name)
      super("Tried to #{action} unspecified class: #{klass_name}")
    end
  end

  class SyntaxError < Exception
    attr_reader :file, :line, :column, :offset, :problem, :context

    def initialize(file, line, col, offset, problem, context)
      err = [problem, context].compact.join(" ")
      super(format("(%s): %s at line %d column %d", file.nil? ? "<unknown>" : file, err, line, col))
      @file = file
      @line = line
      @column = col
      @offset = offset
      @problem = problem
      @context = context
    end
  end

  native_lib "yaml"
  native_func :events, [:string, :int], :any, "spinel_yaml_events"
  native_func :emit, [:any, :int, :int, :int], :string, "spinel_yaml_emit"

  def self.load(yaml, permitted_classes: [Symbol], permitted_symbols: [], aliases: false, filename: nil,
                fallback: nil, symbolize_names: false, freeze: false, strict_integer: false, parse_symbols: true)
    safe_load(yaml, permitted_classes: permitted_classes, permitted_symbols: permitted_symbols,
              aliases: aliases, filename: filename, fallback: fallback, symbolize_names: symbolize_names,
              freeze: freeze, strict_integer: strict_integer, parse_symbols: parse_symbols)
  end

  def self.safe_load(yaml, permitted_classes: [], permitted_symbols: [], aliases: false, filename: nil,
                     fallback: nil, symbolize_names: false, freeze: false, strict_integer: false,
                     parse_symbols: true)
    scanner = ScalarScanner.new(permitted_classes, permitted_symbols: permitted_symbols,
                                strict_integer: strict_integer, parse_symbols: parse_symbols)
    loader = Loader.new(Psych.events(yaml, 0), filename, scanner, aliases: aliases,
                        symbolize_names: symbolize_names, freeze: freeze)
    loader.document? ? loader.document : fallback
  end

  # The first document, read without the safe_load restrictions: aliases
  # and Symbols are allowed, and only what this package cannot build
  # (Date, Time, objects) raises.
  def self.unsafe_load(yaml, filename: nil, fallback: false, symbolize_names: false, freeze: false,
                       strict_integer: false, parse_symbols: true)
    loader = unsafe_loader(Psych.events(yaml, 0), filename, symbolize_names, freeze, strict_integer, parse_symbols)
    loader.document? ? loader.document : fallback
  end

  # Every document of a stream, read as unsafe_load reads one (Psych builds
  # each with to_ruby, outside safe_load). With a block each document is
  # yielded instead, and the answer is nil.
  def self.load_stream(yaml, filename: nil, fallback: [], symbolize_names: false, freeze: false,
                       strict_integer: false, parse_symbols: true)
    loader = unsafe_loader(Psych.events(yaml, 1), filename, symbolize_names, freeze, strict_integer, parse_symbols)
    documents = []
    while loader.document?
      if block_given?
        yield loader.document
      else
        documents << loader.document
      end
    end
    return nil if block_given?
    documents.empty? ? fallback : documents
  end

  # Every document read as safe_load reads one. With a block each document
  # is yielded instead, and the answer is nil.
  def self.safe_load_stream(yaml, filename: nil, permitted_classes: [], aliases: false)
    scanner = ScalarScanner.new(permitted_classes)
    loader = Loader.new(Psych.events(yaml, 1), filename, scanner, aliases: aliases)
    documents = []
    documents << loader.document while loader.document?
    return documents unless block_given?
    documents.each { |d| yield d }
    nil
  end

  def self.unsafe_loader(events, filename, symbolize_names, freeze, strict_integer, parse_symbols)
    scanner = ScalarScanner.new([Symbol], unsafe: true, strict_integer: strict_integer, parse_symbols: parse_symbols)
    Loader.new(events, filename, scanner, aliases: true, symbolize_names: symbolize_names, freeze: freeze, unsafe: true)
  end

  # Psych's dump options: line_width, indentation, canonical, header,
  # version and stringify_names. With an IO the text is written to it and
  # the IO is the answer.
  def self.dump(o, io = nil, options = {})
    if io.is_a?(Hash)
      options = io
      io = nil
    end
    write(Dumper.new(options).dump(o), io)
  end

  # dump that refuses what safe_load would: classes other than true, false,
  # nil, Integer, Float, String, Array and Hash unless permitted_classes
  # names them, Symbols unless permitted, and a repeated Hash or Array
  # unless aliases: true.
  def self.safe_dump(o, io = nil, options = {})
    if io.is_a?(Hash)
      options = io
      io = nil
    end
    write(Dumper.new(options, true).dump(o), io)
  end

  # One document per object.
  def self.dump_stream(*objects)
    Dumper.new.dump_stream(objects)
  end

  def self.write(text, io)
    return text if io.nil?
    io.write(text)
    io
  end

  def self.load_file(filename, permitted_classes: [Symbol], permitted_symbols: [], aliases: false,
                     fallback: nil, symbolize_names: false, freeze: false, strict_integer: false,
                     parse_symbols: true)
    load(File.read(filename), permitted_classes: permitted_classes, permitted_symbols: permitted_symbols,
         aliases: aliases, filename: filename, fallback: fallback, symbolize_names: symbolize_names,
         freeze: freeze, strict_integer: strict_integer, parse_symbols: parse_symbols)
  end

  def self.safe_load_file(filename, permitted_classes: [], permitted_symbols: [], aliases: false,
                          fallback: nil, symbolize_names: false, freeze: false, strict_integer: false,
                          parse_symbols: true)
    safe_load(File.read(filename), permitted_classes: permitted_classes, permitted_symbols: permitted_symbols,
              aliases: aliases, filename: filename, fallback: fallback, symbolize_names: symbolize_names,
              freeze: freeze, strict_integer: strict_integer, parse_symbols: parse_symbols)
  end

  def self.unsafe_load_file(filename, fallback: false, symbolize_names: false, freeze: false,
                            strict_integer: false, parse_symbols: true)
    unsafe_load(File.read(filename), filename: filename, fallback: fallback, symbolize_names: symbolize_names,
                freeze: freeze, strict_integer: strict_integer, parse_symbols: parse_symbols)
  end

  # Types a plain scalar by the YAML 1.1 rules; a quoted one stays a String.
  class ScalarScanner
    TIME = /^-?\d{4}-\d{1,2}-\d{1,2}(?:[Tt]|\s+)\d{1,2}:\d\d:\d\d(?:\.\d*)?(?:\s*(?:Z|[-+]\d{1,2}:?(?:\d\d)?))?$/
    DATE = /^\d{4}-(?:1[012]|0\d|\d)-(?:[12]\d|3[01]|0\d|\d)$/
    FLOAT = /^(?:[-+]?([0-9][0-9_,]*)?\.[0-9]*([eE][-+][0-9]+)?)$/
    INTEGER_STRICT = /^(?:[-+]?0b[_]*[0-1][0-1_]*|[-+]?0[_]*[0-7][0-7_]*|[-+]?(0|[1-9][0-9_]*)|[-+]?0x[_]*[0-9a-fA-F][0-9a-fA-F_]*)$/
    INTEGER_LEGACY = /^(?:[-+]?0b[_,]*[0-1][0-1_,]*|[-+]?0[_,]*[0-7][0-7_,]*|[-+]?(?:0|[1-9](?:[0-9]|,[0-9]|_[0-9])*)|[-+]?0x[_,]*[0-9a-fA-F][0-9a-fA-F_,]*)$/

    # A dumping scanner only tells Strings from the rest: a Date or a
    # Symbol is not a String, and nothing is refused. An unsafe one refuses
    # no class, so a Date or Time it cannot build is not read. A strict one
    # reads no commas in integers.
    def initialize(permitted_classes, permitted_symbols: [], dumping: false, unsafe: false,
                   strict_integer: false, parse_symbols: true)
      @permitted_classes = permitted_classes
      @permitted_symbols = permitted_symbols.map(&:to_s)
      @dumping = dumping
      @unsafe = unsafe
      @integer = strict_integer ? INTEGER_STRICT : INTEGER_LEGACY
      @parse_symbols = parse_symbols
    end

    def tokenize(string)
      return nil if string.empty?
      if string.match?(%r{^[^\d.:-]?[[:alpha:]_\s!@#$%\^&*(){}<>|/\\~;=]+}) || string.match?(/\n/)
        return string if string.length > 5
        if string.match?(/^[^ytonf~]/i)
          string
        elsif string == "~" || string.match?(/^null$/i)
          nil
        elsif string.match?(/^(yes|true|on)$/i)
          true
        elsif string.match?(/^(no|false|off)$/i)
          false
        else
          string
        end
      elsif string.match?(TIME)
        disallow("Time")
      elsif string.match?(DATE)
        disallow("Date")
      elsif string.match?(/^\+?\.inf$/i)
        Float::INFINITY
      elsif string.match?(/^-\.inf$/i)
        -Float::INFINITY
      elsif string.match?(/^\.nan$/i)
        Float::NAN
      elsif @parse_symbols && string.match?(/^:./)
        if string.match?(/^:(["']).*\1$/)
          symbol(string[2, string.length - 3])
        else
          symbol(string[1, string.length - 1])
        end
      elsif string.match?(/^[-+]?[0-9][0-9_]*(:[0-5]?[0-9]){1,2}$/)
        sexagesimal_int(string)
      elsif string.match?(/^[-+]?[0-9][0-9_]*(:[0-5]?[0-9]){1,2}\.[0-9_]*$/)
        sexagesimal_float(string)
      elsif string.match?(FLOAT)
        if string.match?(/\A[-+]?\.\z/)
          string
        else
          string.delete(",_").sub(/\.([Ee]|$)/, "\\1").to_f
        end
      elsif string.match?(@integer)
        parse_int(string)
      else
        string
      end
    end

    def parse_int(string)
      digits = string.delete(",_")
      sign = 1
      if digits.start_with?("-")
        sign = -1
        digits = digits[1, digits.length - 1]
      elsif digits.start_with?("+")
        digits = digits[1, digits.length - 1]
      end
      if digits.start_with?("0b")
        sign * digits[2, digits.length - 2].to_i(2)
      elsif digits.start_with?("0x")
        sign * digits[2, digits.length - 2].to_i(16)
      elsif digits.length > 1 && digits.start_with?("0")
        sign * digits.to_i(8)
      else
        sign * digits.to_i
      end
    end

    # 1:30 is 5400 and 12:30:45 is 45045: the first part counts hours.
    def sexagesimal_int(string)
      total = 0
      string.split(":").each_with_index { |part, e| total += part.to_i * 60**(e - 2).abs }
      total
    end

    def sexagesimal_float(string)
      total = 0.0
      string.split(":").each_with_index { |part, e| total += part.to_f * 60**(e - 2).abs }
      total
    end

    def symbol(name)
      return name.to_sym if @dumping
      unless @permitted_symbols.empty? || @permitted_symbols.include?(name)
        raise DisallowedClass.new("load", "Symbol")
      end
      raise DisallowedClass.new("load", "Symbol") unless @permitted_classes.include?(Symbol)
      name.to_sym
    end

    def disallow(klass_name)
      return false if @dumping
      if @unsafe || (klass_name == "Time" && @permitted_classes.include?(Time))
        raise NotImplementedError, "yaml: a #{klass_name} value is not read; quote it to load it as a String"
      end
      raise DisallowedClass.new("load", klass_name)
    end
  end

  # Builds the Ruby value of a document from libyaml's parser events
  # (Psych.events: EVENT_FIELDS slots per event).
  class Loader
    EVENT_FIELDS = 8
    EVENT_ERROR = -1
    STREAM_END = 2
    DOCUMENT_START = 3
    DOCUMENT_END = 4
    ALIAS = 5
    SCALAR = 6
    SEQUENCE_START = 7
    SEQUENCE_END = 8
    MAPPING_START = 9
    MAPPING_END = 10

    STR_TAG = "tag:yaml.org,2002:str"

    # An unsafe loader reads as to_ruby does, outside safe_load: what it
    # refuses is only what it cannot build. A freezing one freezes every
    # String, Array and Hash it builds.
    def initialize(events, filename, scanner, aliases: false, symbolize_names: false, freeze: false,
                   unsafe: false)
      @events = events
      @filename = filename
      @aliases = aliases
      @symbolize_names = symbolize_names
      @freeze = freeze
      @unsafe = unsafe
      @scanner = scanner
      @anchors = {}
      @i = 0
      raise_syntax_error if @events.size >= EVENT_FIELDS && type_at(@events.size - EVENT_FIELDS) == EVENT_ERROR
      @i += EVENT_FIELDS while @i < @events.size && type_at(@i) != DOCUMENT_START && type_at(@i) != STREAM_END
    end

    # Whether the stream holds a document.
    def document?
      @i < @events.size && type_at(@i) == DOCUMENT_START
    end

    # The value of the document at @i, leaving @i at the next one. Anchors
    # belong to their document.
    def document
      @anchors = {}
      @i += EVENT_FIELDS
      value = node
      @i += EVENT_FIELDS if @i < @events.size && type_at(@i) == DOCUMENT_END
      value
    end

    def type_at(i)
      @events[i]
    end

    def raise_syntax_error
      e = @events.size - EVENT_FIELDS
      raise SyntaxError.new(@filename, @events[e + 6], @events[e + 7], @events[e + 4], @events[e + 1], @events[e + 2])
    end

    # The value of the node whose event is at @i, leaving @i past it.
    def node
      e = @i
      @i += EVENT_FIELDS
      type = type_at(e)
      if type == SCALAR
        value = scalar(@events[e + 1], @events[e + 3], @events[e + 4] == 1)
        value = value.freeze if @freeze && value.is_a?(String)
        register(@events[e + 2], value)
      elsif type == ALIAS
        raise AliasesNotEnabled.new unless @aliases
        name = @events[e + 1]
        raise AnchorNotDefined.new(name) unless @anchors.key?(name)
        @anchors[name]
      elsif type == SEQUENCE_START
        collection_tag(@events[e + 3])
        list = register(@events[e + 2], [])
        list << node while type_at(@i) != SEQUENCE_END
        @i += EVENT_FIELDS
        @freeze ? list.freeze : list
      elsif type == MAPPING_START
        collection_tag(@events[e + 3])
        hash = register(@events[e + 2], {})
        mapping(hash) while type_at(@i) != MAPPING_END
        @i += EVENT_FIELDS
        @freeze ? hash.freeze : hash
      else
        raise SyntaxError.new(@filename, @events[e + 6], @events[e + 7], 0, "unexpected event #{type}", nil)
      end
    end

    # One key and its value, added to hash. A << key that is not tagged as a
    # String merges a mapping, or a list of them, where it stands; later keys
    # still override what it brought.
    def mapping(hash)
      key_tag = @events[@i + 3]
      key = node
      value_type = type_at(@i)
      value = node
      if key == "<<" && key_tag != STR_TAG && value_type != SCALAR
        if value.is_a?(Hash)
          hash.merge!(value)
          return
        elsif value.is_a?(Array) && value.all? { |v| v.is_a?(Hash) }
          merged = {}
          value.reverse_each { |v| merged.merge!(v) }
          hash.merge!(merged)
          return
        end
      end
      key = key.to_sym if @symbolize_names && key.is_a?(String)
      hash[key] = value
    end

    def register(anchor, value)
      @anchors[anchor] = value unless anchor.nil?
      value
    end

    def scalar(value, tag, quoted)
      return value if quoted
      return @scanner.tokenize(value) if tag.nil?
      if tag == STR_TAG || tag == "!str"
        value
      elsif tag == "tag:yaml.org,2002:float" || tag == "!float"
        @scanner.tokenize(value).to_f
      elsif tag.start_with?("!ruby/sym")
        @scanner.symbol(value)
      elsif tag.start_with?("!ruby/") || tag == "!binary" || tag == "tag:yaml.org,2002:binary"
        unsupported_tag(tag)
      else
        @scanner.tokenize(value)
      end
    end

    def collection_tag(tag)
      return if tag.nil?
      unsupported_tag(tag) if tag.start_with?("!ruby/") || tag.start_with?("!map:") || tag.start_with?("!seq:") ||
                              tag == "!set" || tag == "!omap" || tag.start_with?("tag:yaml.org,2002:set") ||
                              tag.start_with?("tag:yaml.org,2002:omap")
    end

    # Tags that build objects: !ruby/object is a disallowed class, as in
    # safe_load; the rest are not read.
    def unsupported_tag(tag)
      if tag.start_with?("!ruby/object:") && !@unsafe
        raise DisallowedClass.new("load", tag[13, tag.length - 13])
      end
      raise NotImplementedError, "yaml: the tag #{tag} is not read"
    end
  end

  # Writes a value as YAML the way Psych's YAMLTree does for data -- or, when
  # restricted, its RestrictedYAMLTree: Hashes
  # and Arrays in block style, each scalar in the style Psych picks for it,
  # and a Hash or Array met a second time as an alias of the first (&1, *1,
  # numbered in the order the repeats are met).
  class Dumper
    EVENT_FIELDS = 8
    STREAM_START = 1
    STREAM_END = 2
    DOCUMENT_START = 3
    DOCUMENT_END = 4
    ALIAS = 5
    SCALAR = 6
    SEQUENCE_START = 7
    SEQUENCE_END = 8
    MAPPING_START = 9
    MAPPING_END = 10

    ANY = 0
    PLAIN = 1
    SINGLE_QUOTED = 2
    DOUBLE_QUOTED = 3
    LITERAL = 4
    FOLDED = 5
    BLOCK = 1

    DEFAULT_PERMITTED = [TrueClass, FalseClass, NilClass, Integer, Float, String, Array, Hash]

    def initialize(options = {}, restricted = false)
      @restricted = restricted
      @permitted_classes = DEFAULT_PERMITTED + (options[:permitted_classes] || [])
      @permitted_symbols = options[:permitted_symbols] || []
      @aliases = options[:aliases] || false
      @line_width = options[:line_width]
      if @line_width && @line_width < 0
        raise ArgumentError, "Invalid line_width #{@line_width}, must be non-negative or -1 for unlimited." unless @line_width == -1
        @line_width = nil
      end
      @width = options.key?(:line_width) ? options[:line_width] : 0
      @indent = options.key?(:indentation) ? options[:indentation] : 2
      @canonical = options[:canonical] ? 1 : 0
      @version = version_directive(options)
      @stringify_names = options[:stringify_names]
      @events = []
      @scanner = ScalarScanner.new([Symbol], dumping: true)
      @seen = {}
      @anchor_ids = {}
      @count = 0
      @emitted = {}
    end

    def dump(o)
      dump_stream([o])
    end

    # Anchors are numbered across the whole stream, as Psych's one visitor
    # does.
    def dump_stream(objects)
      objects.each { |o| number_repeats(o) }
      event(STREAM_START, nil, nil, nil, 0, 0, 0, 0)
      objects.each do |o|
        event(DOCUMENT_START, @version, nil, nil, 0, 0, 0, 0)
        accept(o)
        event(DOCUMENT_END, nil, nil, nil, 0, 0, 0, 1)
      end
      event(STREAM_END, nil, nil, nil, 0, 0, 0, 0)
      Psych.emit(@events, @width, @indent, @canonical)
    end

    # "1.1" for header: true, or the version option as Psych reads it.
    def version_directive(options)
      if options.key?(:version)
        v = options[:version]
        return "#{v[0]}.#{v[1]}" if v.is_a?(Array)
        return v.split(".").map(&:to_i).join(".") if v.is_a?(String)
        return "1.1"
      end
      options[:header] ? "1.1" : nil
    end

    def event(type, value, anchor, tag, plain, quoted, style, implicit)
      @events << type << value << anchor << tag << plain << quoted << style << implicit
    end

    # The anchor numbers, walking in the order accept emits: a Hash or Array
    # met again takes the next number the first time it repeats, and its
    # contents are not walked again.
    def number_repeats(o)
      return unless o.is_a?(Hash) || o.is_a?(Array)
      id = o.object_id
      if @seen.key?(id)
        @anchor_ids[id] = (@count += 1) unless @anchor_ids.key?(id)
        return
      end
      @seen[id] = true
      if o.is_a?(Hash)
        o.each do |k, v|
          number_repeats(k)
          number_repeats(v)
        end
      else
        o.each { |v| number_repeats(v) }
      end
    end

    def accept(o)
      restrict(o) if @restricted
      if o.is_a?(Hash)
        collection(o, MAPPING_START, MAPPING_END)
      elsif o.is_a?(Array)
        collection(o, SEQUENCE_START, SEQUENCE_END)
      elsif o.is_a?(String)
        string(o)
      elsif o.nil?
        event(SCALAR, "", nil, "tag:yaml.org,2002:null", 1, 0, ANY, 0)
      elsif o.is_a?(Symbol)
        symbol(o)
      elsif o.is_a?(Float)
        float(o)
      elsif o.is_a?(Integer) || o == true || o == false
        event(SCALAR, o.to_s, nil, nil, 1, 0, ANY, 0)
      else
        raise NotImplementedError, "yaml: a #{o.class} is not dumped"
      end
    end

    def restrict(o)
      if !@aliases && (o.is_a?(Hash) || o.is_a?(Array)) && @emitted.key?(o.object_id)
        raise BadAlias, "Tried to dump an aliased object"
      end
      if o.is_a?(Symbol)
        unless @permitted_classes.include?(Symbol) || @permitted_symbols.include?(o)
          raise DisallowedClass.new("dump", "Symbol(#{o.inspect})")
        end
      elsif !@permitted_classes.include?(o.class)
        raise DisallowedClass.new("dump", o.class.name)
      end
    end

    def collection(o, start_type, end_type)
      id = o.object_id
      if @emitted.key?(id)
        event(ALIAS, @anchor_ids[id].to_s, nil, nil, 0, 0, 0, 0)
        return
      end
      @emitted[id] = true
      anchor = @anchor_ids.key?(id) ? @anchor_ids[id].to_s : nil
      event(start_type, nil, anchor, nil, 0, 0, BLOCK, 1)
      if o.is_a?(Hash)
        o.each do |k, v|
          accept(@stringify_names && k.is_a?(Symbol) ? k.to_s : k)
          accept(v)
        end
      else
        o.each { |v| accept(v) }
      end
      event(end_type, nil, nil, nil, 0, 0, 0, 0)
    end

    # A String that would read back as something else is quoted; one with a
    # line break inside is a literal block.
    def string(o)
      if o.encoding == Encoding::BINARY && !o.ascii_only?
        raise NotImplementedError, "yaml: a binary String is not dumped"
      end
      plain = 1
      quoted = 1
      tag = nil
      style = PLAIN
      if o.match?(/\n(?!\Z)/)
        style = LITERAL
      elsif o == "<<"
        style = SINGLE_QUOTED
        tag = "tag:yaml.org,2002:str"
        plain = 0
        quoted = 0
      elsif o == "y" || o == "Y" || o == "n" || o == "N"
        style = DOUBLE_QUOTED
      elsif @line_width && o.length > @line_width
        style = FOLDED
      elsif o.match?(/^[^[:word:]][^"]*$/)
        style = DOUBLE_QUOTED
      elsif !@scanner.tokenize(o).is_a?(String) || o.match?(/\A0[0-7]*[89]/)
        style = SINGLE_QUOTED
      end
      event(SCALAR, o, nil, tag, plain, quoted, style, 0)
    end

    def symbol(o)
      if o.empty?
        event(SCALAR, "", nil, "!ruby/symbol", 0, 0, ANY, 0)
      else
        event(SCALAR, ":#{o}", nil, nil, 1, 0, ANY, 0)
      end
    end

    def float(o)
      text = if o.nan?
               ".nan"
             elsif o.infinite?
               o > 0 ? ".inf" : "-.inf"
             else
               o.to_s
             end
      event(SCALAR, text, nil, nil, 1, 0, ANY, 0)
    end
  end
end

class Object
  def to_yaml(options = {})
    Psych.dump(self, options)
  end
end

YAML = Psych
