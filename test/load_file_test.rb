require "yaml"
require "tmpdir"

# load_file reads a Rails-style database.yml with a shared anchor; an empty file loads as nil.
path = File.join(Dir.tmpdir, "spinel_yaml_load_file_#{Process.pid}.yml")
File.write(path, "default: &default\n  adapter: sqlite3\n  pool: 5\n\ndevelopment:\n  <<: *default\n  database: dev.sqlite3\n")
config = YAML.load_file(path, aliases: true)
p config["development"]
p config["development"]["pool"] + 1
p YAML.safe_load_file(path, aliases: true).keys
File.write(path, "")
p YAML.load_file(path)
File.delete(path)
