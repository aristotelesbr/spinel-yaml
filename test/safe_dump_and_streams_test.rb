require "yaml"

# safe_dump refuses what safe_load would refuse; dump_stream writes one
# document per object; safe_load_stream reads each as safe_load does.
def show
  p yield
rescue Psych::Exception => e
  p [e.class, e.message]
end

shared = [1, 2]
show { YAML.safe_dump({ "a" => [1, "x", nil, true, 1.5] }) }
show { YAML.safe_dump({ "a" => :s }) }
show { YAML.safe_dump({ "a" => :s }, permitted_symbols: [:s]) }
show { YAML.safe_dump({ "a" => :s }, permitted_classes: [Symbol]) }
show { YAML.safe_dump({ "a" => shared, "b" => shared }) }
show { YAML.safe_dump({ "a" => shared, "b" => shared }, aliases: true) }
show { YAML.safe_dump({ "a" => 1 }, line_width: -1, header: true) }
print YAML.dump_stream({ "a" => 1 }, [2], "three")
p YAML.safe_load_stream("--- 1\n--- {a: x}\n")
p YAML.safe_load_stream("--- :s\n", permitted_classes: [Symbol])
p YAML.safe_load_stream("a: &x [1]\nb: *x\n", aliases: true)
p YAML.safe_load_stream("")
["--- :s\n", "--- &x [1]\n--- *x\n"].each do |doc|
  begin
    YAML.safe_load_stream(doc)
  rescue Psych::Exception => e
    p [e.class, e.message]
  end
end
out = []
YAML.safe_load_stream("--- 1\n--- 2\n") { |d| out << d }
p out
