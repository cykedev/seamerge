#!/bin/bash
#
# Builds Seamerge from this clone and copies it into the Applications folder.
#
# Usage: Scripts/install.sh [--to <folder>]
#
#   --to <folder>  Install into <folder> instead of /Applications.
#
# The app is built in the Release configuration and signed ad hoc, which is
# enough to run it on this Mac. If the folder already holds Seamerge, the
# script asks before it replaces it. The build goes to .build/install; the log
# of the build is .build/install/build.log.

set -euo pipefail

usage() {
  echo "usage: Scripts/install.sh [--to <folder>]" >&2
  exit 2
}

destination=/Applications
case $# in
  0) ;;
  2) [ "$1" = --to ] && destination=$2 || usage ;;
  *) usage ;;
esac

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [ ! -d "$destination" ]; then
  echo "error: $destination is not a folder" >&2
  exit 1
fi

build=.build/install
log=$build/build.log
mkdir -p "$build"

# Packages come from a cache of the repository, and the keychain is never asked
# for credentials of GitHub, so that no dialog stops the build.
echo "Building Seamerge (Release)…"
if ! xcodebuild -project App/Seamerge.xcodeproj -scheme Seamerge -configuration Release \
  -derivedDataPath "$build/DerivedData" -packageCachePath "$root/.build/package-cache" \
  -packageAuthorizationProvider netrc -onlyUsePackageVersionsFromResolvedFile \
  build > "$log" 2>&1; then
  grep -E 'error:' "$log" | head -20 >&2 || true
  echo "error: the build failed; the full log is $log" >&2
  exit 1
fi
app=$build/DerivedData/Build/Products/Release/Seamerge.app

# Xcode signs the app ad hoc with the Hardened Runtime but leaves Sparkle with
# the signature of its developer, and the runtime then refuses to load it. An
# app signed ad hoc can load no framework under the runtime at all, so the
# whole bundle is signed ad hoc without it; the notarized release keeps it.
codesign --force --deep --sign - --preserve-metadata=entitlements "$app" \
  >> "$log" 2>&1 || {
  echo "error: the app could not be signed; the full log is $log" >&2
  exit 1
}

target=$destination/Seamerge.app
if [ -e "$target" ]; then
  if pgrep -qf "^$target/Contents/MacOS/Seamerge"; then
    echo "error: Seamerge is running from $target; quit it first" >&2
    exit 1
  fi
  read -r -p "$target exists. Replace it? [y/N] " answer
  case $answer in
    y | Y | yes | Yes) ;;
    *)
      echo "Nothing installed."
      exit 1
      ;;
  esac
fi

# Copy next to the target first, so that a failed copy leaves the installed
# app as it was.
staging=$(mktemp -d "$destination/.Seamerge-install.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Seamerge.app"
rm -rf "$target"
mv "$staging/Seamerge.app" "$target"

echo "Installed $target"
echo "To make Git use it, open Seamerge and choose Seamerge > Set Up Git Integration…"
