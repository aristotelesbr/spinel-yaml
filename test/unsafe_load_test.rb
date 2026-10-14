require "yaml"
require "tmpdir"

# unsafe_load reads aliases and Symbols without being asked; an empty
# document answers false, and objects it cannot build still raise.
p YAML.unsafe_load("a: &x [1]\nb: *x\nc: :s\n")
p YAML.unsafe_load("")
p YAML.unsafe_load("", fallback: nil)
p YAML.unsafe_load("{a: 1}", symbolize_names: true)
path = File.join(Dir.tmpdir, "spinel_yaml_unsafe_#{Process.pid}.yml")
File.write(path, "base: &b {k: 1}\nuse:\n  <<: *b\n")
p YAML.unsafe_load_file(path)
File.write(path, "")
p YAML.unsafe_load_file(path)
File.delete(path)
