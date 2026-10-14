require "yaml"
require "stringio"

# Psych's dump options, and an IO to write to.
long = "x " * 50
print YAML.dump({ "a" => long }, line_width: 20)
print YAML.dump({ "a" => long }, line_width: -1)
print YAML.dump({ "a" => "word " * 30 })
print YAML.dump({ "a" => [1, { "b" => 2 }], "c" => { "d" => [3] } }, indentation: 4)
print YAML.dump({ "a" => 1 }, header: true)
print YAML.dump({ "a" => 1 }, version: [1, 2])
print YAML.dump({ "a" => 1 }, version: "1.1")
print YAML.dump({ :a => 1, "b" => :c }, stringify_names: true)
print YAML.dump({ "a" => [1, "x"] }, canonical: true)
print({ "a" => long }.to_yaml(line_width: 30))
begin
  YAML.dump({ "a" => 1 }, line_width: -2)
rescue ArgumentError => e
  p [e.class, e.message]
end
io = StringIO.new
r = YAML.dump({ "a" => 1 }, io)
p [io.string, r.equal?(io)]
io = StringIO.new
YAML.dump([1], io, header: true)
p io.string
