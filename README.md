# yaml for Spinel

`require "yaml"` for [Spinel](https://github.com/matz/spinel), which ships no YAML support of its own. It reads and writes YAML the way Psych does on CRuby: the same values, the same output, the same errors.

```ruby
require "yaml"

config = YAML.load_file("config/database.yml", aliases: true)
config["development"]
# => {"adapter" => "sqlite3", "pool" => 5, "database" => "storage/development.sqlite3"}

print YAML.dump({ "name" => "app", "ports" => [80, 443], "debug" => false })
# ---
# name: app
# ports:
# - 80
# - 443
# debug: false
```

## Installing

Add it to your project's `spin.toml`:

```toml
[dependencies]
yaml = { git = "https://github.com/aristotelesbr/spinel-yaml" }
```

When Spinel ships YAML of its own, remove the line; the code that uses it does not change.

## What it covers

### Loading

| Method | Reads | Restrictions |
|---|---|---|
| `YAML.load`, `YAML.load_file` | the first document | aliases only with `aliases: true` |
| `YAML.safe_load`, `YAML.safe_load_file` | the first document | aliases only with `aliases: true`; Symbols only when permitted |
| `YAML.unsafe_load`, `YAML.unsafe_load_file` | the first document | none (an empty document answers `false`) |
| `YAML.load_stream` | every document | none |
| `YAML.safe_load_stream` | every document | as `safe_load` |

What a document becomes:

| YAML | Ruby |
|---|---|
| mappings and sequences, block or flow | `Hash` (any scalar as a key: `1: one`, `true: t`) and `Array` |
| `yes`, `No`, `on`, `off`, `true` | `true` / `false` (YAML 1.1, as Psych) |
| `~`, `null`, an empty value | `nil` |
| `12`, `0755`, `0x1F`, `0b101`, `1_000`, `1,000`, `1:30` | `Integer` (octal, hex, binary, base 60) |
| `1.5`, `.5`, `1.0e+3`, `.inf`, `-.inf`, `.nan` | `Float` |
| `:name` | `Symbol` (when permitted) |
| quoted scalars, `\|` and `>` blocks | `String`, with escapes and folding |
| `&anchor`, `*alias`, `<<: *defaults` | the same object again; merge keys |
| `!!str`, `!!int`, `!!float`, `!ruby/sym` | as tagged |

A malformed document raises `Psych::SyntaxError` with libyaml's message, line and column, byte for byte as on CRuby.

### Dumping

| Method | Writes |
|---|---|
| `YAML.dump`, `Object#to_yaml` | one document |
| `YAML.safe_dump` | one document, refusing Symbols, other classes and repeated collections unless permitted |
| `YAML.dump_stream` | one document per argument |

Hashes, Arrays, Strings, Symbols, Integers, Floats, `true`, `false` and `nil` are written in the style Psych picks: a String that would read back as something else is quoted (`'123'`, `'true'`), one with a line break is a literal block, and a Hash or Array met twice becomes `&1` / `*1`. With an IO as the second argument the text is written to it.

### Options

| Option | Methods | Effect |
|---|---|---|
| `permitted_classes:` | `safe_load`, `load`, `safe_dump` | classes allowed beyond the basic ones (`Symbol`) |
| `permitted_symbols:` | `safe_load`, `load`, `safe_dump` | which Symbols are allowed |
| `aliases:` | `load`, `safe_load`, `safe_dump` | allow anchors and aliases |
| `symbolize_names:` | all loaders | String keys become Symbols |
| `freeze:` | all loaders | every String, Array and Hash is frozen |
| `strict_integer:` | all loaders | `1,000` stays a String |
| `parse_symbols:` | all loaders | `false` keeps `:name` a String |
| `fallback:` | all loaders | the answer for an empty document |
| `filename:` | `load`, `safe_load`, `unsafe_load`, `load_stream` | named in `Psych::SyntaxError` |
| `line_width:` | `dump`, `safe_dump`, `to_yaml` | fold long Strings; `-1` is unlimited |
| `indentation:` | `dump`, `safe_dump`, `to_yaml` | spaces per level |
| `canonical:` | `dump`, `safe_dump`, `to_yaml` | canonical YAML |
| `header:`, `version:` | `dump`, `safe_dump`, `to_yaml` | write a `%YAML` directive |
| `stringify_names:` | `dump`, `safe_dump`, `to_yaml` | Symbol keys are written as Strings |

Under CRuby, `require "yaml"` of this package hands over to the real Psych, so the same program runs on both.

## Not supported yet

| What | What happens |
|---|---|
| Date and Time values (`2026-10-14`) | `Psych::DisallowedClass` from `load` / `safe_load`, as on CRuby; `NotImplementedError` from `unsafe_load` and `load_stream`, which would build them (Spinel has no `Date` class yet) |
| Tags that build objects | `!ruby/object:...` raises `Psych::DisallowedClass` from `safe_load`; other `!ruby/...`, `!binary`, `!set` and `!omap` raise `NotImplementedError` |
| Dumping objects other than the classes above, and binary Strings | `NotImplementedError` |
| `load_stream` / `safe_load_stream` with a block | each document is yielded; the answer is `nil` (Psych answers its parser) |
| `parse`, `parse_stream`, the node tree, `Psych::Handler`, `to_json` | not defined: refused at compile time |

## How it works

libyaml, the C library Psych itself is built on, reads and writes the text. Everything Psych does on top of it (typing scalars, building Hashes and Arrays, aliases, the `safe_load` rules, the style of each dumped scalar) is written in Ruby. Between them, a small C bridge passes libyaml's events across as a flat Array and decides nothing.

| File | Role |
|---|---|
| `yaml.rb` | the Ruby API and everything Psych does above libyaml |
| `sp_yaml.c` | the bridge: libyaml's parser events to Ruby, and Ruby's events to libyaml's emitter |
| `vendor/libyaml/` | libyaml 0.2.5, unchanged (MIT, see `vendor/libyaml/License`) |
| `native/libyaml_*.c` | one wrapper per libyaml source, supplying the definitions libyaml's own build passes (spin compiles package C with `-I <package root>` only, and `yaml_private.h` has no include guard) |
| `yaml.h` | answers libyaml's `#include <yaml.h>` with the vendored header |

## Testing

```sh
spin test                       # each test/*.rb compared against CRuby + Psych
SPINEL_GC_STRESS=1 spin test    # the same with a collection every few KB
```

The tests are written against CRuby 4.0 (Psych 5.3); put its `ruby` first in `PATH`. Tested with Spinel `6f88ebcc3` and CRuby 4.0.7.

`.github/workflows/test.yml` runs both on Linux and macOS on every push
against that Spinel revision, and every day against Spinel master.

## License

MIT, see `MIT-LICENSE`.
