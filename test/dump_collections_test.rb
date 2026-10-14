require "yaml"

# Hashes and Arrays in block style, any scalar as a key, and a Hash or Array
# met twice as an anchor and its alias.
print YAML.dump({ "a" => 1, "b" => [1, "two", nil], "c" => { "d" => true } })
print YAML.dump([1, [2, [3]], { "k" => [] }, {}])
print YAML.dump({ 1 => "one", true => "t", nil => "n", :sym => "s", 1.5 => "f" })
print YAML.dump("adapter" => "sqlite3", "pool" => 5, "database" => "storage/dev.sqlite3")
shared = { "x" => 1 }
list = [1, 2]
print YAML.dump({ "a" => shared, "b" => shared, "c" => list, "d" => [list, shared] })
print({ "name" => "app", "tags" => ["a", "b"] }.to_yaml)
print [1, "x"].to_yaml
print "text".to_yaml
p YAML.load(YAML.dump({ "a" => ["1", 1, "yes", true, nil, "", "x\ny"] }))
print YAML.dump({ "a" => { "x" => 1 }, "b" => { "x" => 1 } })
print YAML.dump([shared, shared.dup, shared])
