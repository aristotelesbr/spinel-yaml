require "yaml"

# Malformed documents raise Psych::SyntaxError with libyaml's problem and position.
["a: [1", "a: 1\n b: 2\n", "a: b: c\n", "- a\n-b\n", "a: \"unterminated\n",
 "- 1\na: 2\n", "a: {b: 1", "x: [:s]\n"].each do |doc|
  begin
    YAML.load(doc)
    puts "no error"
  rescue Psych::SyntaxError => e
    p [e.message, e.line, e.column, e.problem, e.context]
  end
end
begin
  YAML.load("a: [1", filename: "config.yml")
rescue Psych::SyntaxError => e
  p e.message
end
