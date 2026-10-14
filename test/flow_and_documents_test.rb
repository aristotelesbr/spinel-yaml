require "yaml"

# Flow collections, comments, and the first document of a stream.
p YAML.load("a: [1, two, 3.0]\nb: {x: y, z: ~}\n")
p YAML.load("a: [1, [2, 3], {b: c}]\nc: [ ]\nd: { }\n")
p YAML.load("a: [1,\n  2, # c\n  3]\n")
p YAML.load("x: [a: 1, b]\n")
p YAML.load("a: 1 # c\n# c2\nb: 2")
p YAML.load("")
p YAML.load("# only comment\n")
p YAML.load("%YAML 1.1\n---\na: 1\n")
p YAML.load("a: 1\n---\nb: 2\n")
p YAML.load("a: 1\n---\n[unclosed\n")
p YAML.load("a: 1\r\nb: 2\r\n")
