# yaml for Spinel

`YAML.load` / `YAML.dump` for [Spinel](https://github.com/matz/spinel), which ships no YAML support of its own. libyaml (the parser and emitter Psych uses, vendored unchanged) reads and writes the text, and the rest of what Psych does on top of it is written in Ruby:

- Scalars typed as Psych's `ScalarScanner` types them (YAML 1.1 booleans such as `yes`/`off`, `0755` octal, `1,000`, base 60 `1:30`, `.inf`, `:symbol`)
- Hashes with any scalar key (`1: one`, `true: t`), Arrays, anchors and aliases, merge keys (`<<: *defaults`)
- Psych's load modes: `load` / `load_file` / `safe_load` / `safe_load_file` refuse aliases unless `aliases: true`, `safe_load` refuses Symbol unless permitted, both refuse Date / Time and object tags, with Psych's exception classes and messages (`Psych::SyntaxError` carries libyaml's problem, context, line and column)
- `symbolize_names:`, `fallback:`, `filename:`, `freeze:`, `strict_integer:`, `parse_symbols:`, `permitted_symbols:`
- `unsafe_load` / `unsafe_load_file`, with aliases and Symbols allowed
- `load_stream` for every document of a stream, read without the `safe_load` restrictions as in Psych (with a block, each document is yielded and the answer is `nil`)
- `YAML.dump` and `Object#to_yaml` for Hashes, Arrays and scalars, in the style Psych's `YAMLTree` picks for each (quoted when a String would read back as something else, literal blocks for multi line Strings, `&1` / `*1` for a repeated Hash or Array)
- `safe_dump` (refusing Symbols, other classes and repeated collections as Psych's does), `dump_stream`, `safe_load_stream`
- Psych's dump options: `line_width:`, `indentation:`, `canonical:`, `header:`, `version:`, `stringify_names:`, and an IO to write to

Under CRuby, `require "yaml"` of this package hands over to the real Psych, which makes `spin test` compare this implementation against Psych.

## Installing

```toml
[dependencies]
yaml = { git = "https://github.com/aristotelesbr/spinel-yaml" }
```

## Not supported yet

- Dumping objects other than Hash, Array, String, Symbol, Integer, Float, true, false and nil, and binary Strings
- Date and Time values (`Psych::DisallowedClass`, as with `load`; Spinel has no Date class yet)
- Tags that build objects (`!ruby/object` raises `Psych::DisallowedClass`, other `!ruby/...`, `!binary`, `!set` and `!omap` raise `NotImplementedError`)
- `parse`, `parse_stream` and the node tree, `Psych::Handler`, `to_json`

## Layout

- `yaml.rb`: the Ruby API, scalar typing, the building of values from parser events, and the events and scalar styles of a dump
- `sp_yaml.c`: passes libyaml's parser events to Ruby, and Ruby's events to libyaml's emitter, as a flat Array, deciding nothing
- `native/libyaml_*.c`: one wrapper per libyaml source, supplying the definitions libyaml's own build passes (spin compiles package C with `-I <package root>` only, and `yaml_private.h` has no include guard)
- `yaml.h`: answers libyaml's `#include <yaml.h>` with the vendored header
- `vendor/libyaml`: libyaml 0.2.5, unchanged (MIT, see `vendor/libyaml/License`)

## Testing

```sh
spin test                       # each test/*.rb compared against CRuby + Psych
SPINEL_GC_STRESS=1 spin test    # the same with a collection every few KB
```

## License

MIT, see `MIT-LICENSE`.
