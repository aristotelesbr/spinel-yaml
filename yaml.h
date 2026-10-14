/* libyaml's sources include <yaml.h>; spin compiles package C with
   -I <package root>, so this file answers that include with the vendored
   header and vendor/libyaml stays as released. */
#include "vendor/libyaml/include/yaml.h"
