require "yaml"

# Aliases need aliases: true; << merges; safe_load permits no Symbol; dates
# and object tags are disallowed classes.
def show
  p yield
rescue Psych::Exception => e
  p [e.class, e.message]
end

show { YAML.load("a: &x 1\nb: *x\n") }
show { YAML.load("a: &x 1\nb: *x\n", aliases: true) }
show { YAML.load("a: *nope\n", aliases: true) }
h = YAML.load("a: &x [1, 2]\nb: *x\n", aliases: true)
p h["a"].equal?(h["b"])
show { YAML.load("base: &b {k: 1, m: 2}\ndev:\n  k: 0\n  <<: *b\n  m: 3\n", aliases: true) }
show { YAML.load("a: &a {x: 1}\nb: &b {y: 2}\nc:\n  <<: [*a, *b]\n", aliases: true) }
show { YAML.load("a: {x: 1}\nb:\n  !!str '<<': z\n") }
show { YAML.safe_load("a: [x, 1]") }
show { YAML.safe_load("a: :s") }
show { YAML.safe_load("a: :s", permitted_classes: [Symbol]) }
show { YAML.load("a: 2026-10-14") }
show { YAML.load("a: 2026-10-14 10:00:00") }
show { YAML.load("a: !ruby/object:Object {}\n") }
show { YAML.load("a: 1\n1: b\n", symbolize_names: true) }
show { YAML.load("a: {b: [1, {c: d}]}", symbolize_names: true) }
show { YAML.load("", fallback: {}) }
