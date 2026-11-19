#!/bin/bash
#
# Writes every string catalog of the repository as Xcode writes it, so that
# opening a catalog in Xcode changes nothing. Scripts/check.sh fails while a
# catalog is in another form.
#
# Usage: Scripts/format-strings.sh [--check]
#
#   --check  Change nothing; name each catalog in another form and exit with 1.

set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

catalogs=()
while IFS= read -r -d '' file; do
  [ -f "$file" ] && catalogs+=("$file")
done < <(git ls-files -z --cached --others --exclude-standard -- '*.xcstrings')
[ ${#catalogs[@]} -eq 0 ] && exit 0
swift Scripts/Support/FormatStringCatalog.swift "$@" "${catalogs[@]}"
