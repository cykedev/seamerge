#!/bin/bash
#
# Checks that the current commit can be released, and prints the commands
# that tag and push it.
#
# Usage: Scripts/release-ready.sh
#
# The version is MARKETING_VERSION in App/Config/Version.xcconfig and the tag
# is v<version>. The checks, in this order: CHANGELOG.md has a section for the
# version; the tag exists neither here nor on the remote; the working tree is
# clean; the commit is on the remote branch the current branch tracks; and
# Scripts/check.sh passes for this commit. The script changes nothing: it
# stops at the first failed check, or prints the commands and stops.

set -euo pipefail

if [ $# -ne 0 ]; then
  echo "usage: Scripts/release-ready.sh" >&2
  exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fail() {
  echo "not ready: $1" >&2
  exit 1
}

version=$(sed -n 's/^MARKETING_VERSION = //p' App/Config/Version.xcconfig)
[ -n "$version" ] || fail "App/Config/Version.xcconfig sets no MARKETING_VERSION"
tag=v$version
echo "Version $version, tag $tag"

[ -f CHANGELOG.md ] || fail "there is no CHANGELOG.md"
grep -Eq "^## \[$(printf '%s' "$version" | sed 's/\./\\./g')\]" CHANGELOG.md \
  || fail "CHANGELOG.md has no section '## [$version]'"
echo "ok  CHANGELOG.md has a section for $version"

if git rev-parse --quiet --verify "refs/tags/$tag" > /dev/null; then
  fail "the tag $tag exists already"
fi
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2> /dev/null) \
  || fail "the branch $(git branch --show-current) tracks no remote branch"
remote=${upstream%%/*}
remote_tags=$(git ls-remote --tags "$remote" "refs/tags/$tag") \
  || fail "the remote $remote cannot be reached"
[ -z "$remote_tags" ] || fail "the tag $tag exists on $remote already"
echo "ok  the tag $tag is free"

[ -z "$(git status --porcelain)" ] || fail "the working tree has changes"
echo "ok  the working tree is clean"

git fetch --quiet "$remote" || fail "the remote $remote cannot be reached"
git merge-base --is-ancestor HEAD "$upstream" || fail "the commit is not on $upstream"
echo "ok  the commit is on $upstream"

echo "Running Scripts/check.sh for $(git rev-parse --short HEAD)…"
Scripts/check.sh || fail "Scripts/check.sh failed"
[ -z "$(git status --porcelain)" ] || fail "Scripts/check.sh changed the working tree"

cat << EOF

Ready to release $version. To tag and push:

  git tag -a $tag -m "Seamerge $version"
  git push $remote $tag
EOF
