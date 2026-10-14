require "yaml"

# freeze:, strict_integer:, parse_symbols: and permitted_symbols: as Psych reads them.
def show
  p yield
rescue Psych::Exception => e
  p [e.class, e.message]
end

h = YAML.load("a: [1, x]\nb: {c: d}\n", freeze: true)
p [h.frozen?, h["a"].frozen?, h["a"][1].frozen?, h["b"].frozen?, h["b"]["c"].frozen?, h.keys[0].frozen?]
h = YAML.load("a: [1, x]\n")
p [h.frozen?, h["a"].frozen?, h["a"][1].frozen?]
p YAML.load_stream("--- [x]\n", freeze: true)[0].frozen?
p YAML.unsafe_load("x", freeze: true).frozen?
show { YAML.load("a: 1,000\nb: 1_000\nc: 0x1F\n", strict_integer: true) }
show { YAML.load("a: 1,000\n") }
show { YAML.load("a: :s\n", parse_symbols: false) }
show { YAML.unsafe_load("a: :s\n", parse_symbols: false) }
show { YAML.safe_load("a: :s\nb: :t\n", permitted_classes: [Symbol], permitted_symbols: [:s]) }
show { YAML.safe_load("a: :s\n", permitted_classes: [Symbol], permitted_symbols: [:s]) }
show { YAML.safe_load("a: :s\n", permitted_symbols: [:s]) }
show { YAML.load("a: :t\n", permitted_symbols: [:s]) }
