# yaml -- YAML.load for Spinel, over the vendored libyaml 0.2.5.
#
# libyaml reads the text (sp_yaml.c hands its parser events over as they
# are); this file turns the events into Ruby values the way Psych does:
# scalars typed by the YAML 1.1 rules, Hashes and Arrays, anchors and
# aliases, << merge keys, and the load / safe_load restrictions with Psych's
# exception classes and messages. See README.md for what is not covered yet.

# Under CRuby (spin test's oracle, or a program run with plain `ruby`) this
# file shadows the stdlib's yaml.rb, so hand over to the real Psych. Spinel
# drops the branch before analysis.
unless RUBY_ENGINE == "spinel"
  require "psych"
  YAML = Psych
  return
end

module Psych
  native_lib "yaml"
  native_func :events, [:string, :int], :any, "spinel_yaml_events"
end

YAML = Psych
