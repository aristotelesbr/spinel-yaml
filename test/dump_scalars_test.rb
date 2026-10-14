require "yaml"

# Each scalar in the style Psych picks: plain when it reads back as itself,
# quoted when it would read back as something else, a literal block when it
# holds a line break.
["plain", "two words", "", " lead", "trail ", "123", "1.5", "true", "yes", "no", "~", "null",
 "y", "n", "Y", "<<", ":sym", "@at", "#hash", "-dash", "- dash", "a: b", "a #b", "[x]", "{x}",
 "'single'", "\"double\"", "09", "019", "0o7", "2026-10-14", "12:30", ".inf", "é", "😀",
 "line1\nline2", "line\n", "a\n\n", "\ttab", "x" * 100].each do |s|
  print YAML.dump(s)
end
[0, -7, 2**40, 1.5, -0.25, 1.0e20, 1.0 / 0, -1.0 / 0, 0.0 / 0, nil, true, false, :sym].each do |v|
  print YAML.dump(v)
end
