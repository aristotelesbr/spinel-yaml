require "yaml"

# Plain scalars typed by the YAML 1.1 rules; quoted and block scalars stay Strings.
%w[~ null Null NULL yes No ON off true FALSE y n 0 -1 +7 0755 0o17 0x1F 0b101 1_000 1,000 08 1.5 1. .5 -.5 1e3
   1.0e+3 .inf -.Inf +.inf 1:30 12:30:45 1:30.5 . +. abc 1abc v1.2.3 1.2.3 12:61 :sym].each do |s|
  p [s, YAML.load("v: #{s}\n")["v"]]
end
p YAML.load("v: .NaN\n")["v"].nan?
p YAML.load("a: \"12\"\nb: 'true'\nc: \"~\"\nd: ':sym'\n")
p YAML.load("a: \"q\\tx\\n\\u00e9\\x41\\U0001F600\"\nb: 'it''s'\n")
p YAML.load("a: |\n  12\nb: >-\n  folded\n  text\n")
p YAML.load("a: !!str 123\nb: !!int '42'\nc: !!float '1'\nd: !custom x\ne: !ruby/sym x\n")
p YAML.load("plain")
p YAML.load("--- 5\n")
