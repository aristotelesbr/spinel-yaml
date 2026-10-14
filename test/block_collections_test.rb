require "yaml"

# Block mappings and sequences, nested by indentation.
p YAML.load("a: 1\nb: two\n")
p YAML.load("a:\n  b:\n    c: 1\n  d: 2\ne: 3\n")
p YAML.load("- a\n- b:\n    c: 1\n- - x\n  - y\n")
p YAML.load("a:\n- 1\n- 2\nb: 3\n")
p YAML.load("- name: x\n  size: 1\n- name: y\n  size: 2\n")
p YAML.load("- \n- x\n")
p YAML.load("a:\nb:  \n")
p YAML.load("a: 1\na: 2\n")
p YAML.load("key with spaces: v\n\"quoted key\": w\n'k2': z\n")
p YAML.load("1: one\ntrue: t\n~: n\n1.5: f\n")
