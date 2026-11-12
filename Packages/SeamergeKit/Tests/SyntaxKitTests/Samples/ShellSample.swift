extension LanguageSample {
  static let shell = LanguageSample(
    language: "Shell", fileName: "build.sh",
    annotated: ###"""
      «c:#!/bin/bash»
      set -euo pipefail

      «c:# Count the arguments: $# is not a comment»
      count=${#array[@]}
      echo «s:"Building $(»basename «s:"$PWD") with ${»count«s:} items"» «c:# trailing comment»
      «k:if» [ -n «s:"$1"» ]; «k:then»
        cat «s:<<-'EOF'»
      «s:	Here document with "quotes" and $HOME»
      «s:	EOF»
      «k:fi»
      printf «s:'%s\n'» «s:'single # quoted'»
      «k:exit» «n:0»
      """###)
}
