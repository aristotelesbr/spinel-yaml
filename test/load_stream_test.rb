require "yaml"

# load_stream answers every document, with aliases and Symbols allowed;
# an empty stream answers the fallback, and a block is handed each document.
p YAML.load_stream("--- 1\n--- {a: 2}\n---\n- x\n")
p YAML.load_stream("")
p YAML.load_stream("", fallback: nil)
p YAML.load_stream("--- :s\n--- &a [1]\n--- {b: 1}\n")
p YAML.load_stream("a: &x 1\nb: *x\n")
p YAML.load_stream("--- {a: 1}\n...\n--- {a: 2}\n", symbolize_names: true)
begin
  YAML.load_stream("--- &x 1\n--- *x\n")
rescue Psych::AnchorNotDefined => e
  p [e.class, e.message]
end
begin
  YAML.load_stream("--- 1\n--- [2\n")
rescue Psych::SyntaxError => e
  p [e.class, e.message]
end
out = []
YAML.load_stream("--- 1\n--- 2\n") { |d| out << d }
p out
