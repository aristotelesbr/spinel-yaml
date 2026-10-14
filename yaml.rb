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
  native_func :emit, [:any], :string, "spinel_yaml_emit"

  def self.load(yaml, permitted_classes: [Symbol], aliases: false, filename: nil,
                fallback: nil, symbolize_names: false)
    safe_load(yaml, permitted_classes: permitted_classes, aliases: aliases,
              filename: filename, fallback: fallback, symbolize_names: symbolize_names)
  end

  def self.safe_load(yaml, permitted_classes: [], aliases: false, filename: nil,
                     fallback: nil, symbolize_names: false)
    loader = Loader.new(Psych.events(yaml, 0), filename, permitted_classes, aliases, symbolize_names)
    loader.document? ? loader.document : fallback
  end

  def self.dump(o)
    Dumper.new.dump(o)
  end

  def self.load_file(filename, permitted_classes: [Symbol], aliases: false,
                     fallback: nil, symbolize_names: false)
    load(File.read(filename), permitted_classes: permitted_classes, aliases: aliases,
         filename: filename, fallback: fallback, symbolize_names: symbolize_names)
  end

  def self.safe_load_file(filename, permitted_classes: [], aliases: false,
                          fallback: nil, symbolize_names: false)
    safe_load(File.read(filename), permitted_classes: permitted_classes, aliases: aliases,
              filename: filename, fallback: fallback, symbolize_names: symbolize_names)
  end

  # Types a plain scalar by the YAML 1.1 rules; a quoted one stays a String.
  class ScalarScanner
    TIME = /^-?\d{4}-\d{1,2}-\d{1,2}(?:[Tt]|\s+)\d{1,2}:\d\d:\d\d(?:\.\d*)?(?:\s*(?:Z|[-+]\d{1,2}:?(?:\d\d)?))?$/
    DATE = /^\d{4}-(?:1[012]|0\d|\d)-(?:[12]\d|3[01]|0\d|\d)$/
    FLOAT = /^(?:[-+]?([0-9][0-9_,]*)?\.[0-9]*([eE][-+][0-9]+)?)$/
    INTEGER = /^(?:[-+]?0b[_,]*[0-1][0-1_,]*|[-+]?0[_,]*[0-7][0-7_,]*|[-+]?(?:0|[1-9](?:[0-9]|,[0-9]|_[0-9])*)|[-+]?0x[_,]*[0-9a-fA-F][0-9a-fA-F_,]*)$/

    # A dumping scanner only tells Strings from the rest: a Date or a
    # Symbol is not a String, and nothing is refused.
    def initialize(permitted_classes, dumping = false)
      @permitted_classes = permitted_classes
      @dumping = dumping
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
      elsif string.match?(/^:./)
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
      elsif string.match?(INTEGER)
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
      raise DisallowedClass.new("load", "Symbol") unless @permitted_classes.include?(Symbol)
      name.to_sym
    end

    def disallow(klass_name)
      return false if @dumping
      if klass_name == "Time" && @permitted_classes.include?(Time)
        raise NotImplementedError, "yaml: a Time value is not read; quote it to load it as a String"
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
    ALIAS = 5
    SCALAR = 6
    SEQUENCE_START = 7
    SEQUENCE_END = 8
    MAPPING_START = 9
    MAPPING_END = 10

    STR_TAG = "tag:yaml.org,2002:str"

    def initialize(events, filename, permitted_classes, aliases, symbolize_names)
      @events = events
      @filename = filename
      @aliases = aliases
      @symbolize_names = symbolize_names
      @scanner = ScalarScanner.new(permitted_classes)
      @anchors = {}
      @i = 0
      raise_syntax_error if @events.size >= EVENT_FIELDS && type_at(@events.size - EVENT_FIELDS) == EVENT_ERROR
      @i += EVENT_FIELDS while @i < @events.size && type_at(@i) != DOCUMENT_START && type_at(@i) != STREAM_END
    end

    # Whether the stream holds a document.
    def document?
      @i < @events.size && type_at(@i) == DOCUMENT_START
    end

    def document
      @i += EVENT_FIELDS
      node
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
        register(@events[e + 2], scalar(@events[e + 1], @events[e + 3], @events[e + 4] == 1))
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
        list
      elsif type == MAPPING_START
        collection_tag(@events[e + 3])
        hash = register(@events[e + 2], {})
        mapping(hash) while type_at(@i) != MAPPING_END
        @i += EVENT_FIELDS
        hash
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
      if tag.start_with?("!ruby/object:")
        raise DisallowedClass.new("load", tag[13, tag.length - 13])
      end
      raise NotImplementedError, "yaml: the tag #{tag} is not read"
    end
  end

  # Writes a value as YAML the way Psych's YAMLTree does for data: Hashes
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
    BLOCK = 1

    def initialize
      @events = []
      @scanner = ScalarScanner.new([Symbol], true)
      @seen = {}
      @anchor_ids = {}
      @count = 0
      @emitted = {}
    end

    def dump(o)
      number_repeats(o)
      event(STREAM_START, nil, nil, nil, 0, 0, 0, 0)
      event(DOCUMENT_START, nil, nil, nil, 0, 0, 0, 0)
      accept(o)
      event(DOCUMENT_END, nil, nil, nil, 0, 0, 0, 1)
      event(STREAM_END, nil, nil, nil, 0, 0, 0, 0)
      Psych.emit(@events)
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
          accept(k)
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

YAML = Psych
