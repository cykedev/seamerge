#!/bin/bash
#
# Builds, signs and notarizes a release of Seamerge, packs it for download and
# writes the feed of updates.
#
# Usage: Scripts/release.sh <keychain-profile> [--site <folder> [--new-feed]]
#
#   <keychain-profile>  The profile that `xcrun notarytool store-credentials`
#                       saved in the keychain; the script reads only its name.
#   --site <folder>     The folder of the website: its appcast.xml is the feed
#                       the new one builds on, and the new feed is copied there.
#                       Without it, the feed builds on the one online.
#   --new-feed          Start a new feed in a website folder that has no
#                       appcast.xml yet; without it, such a folder is refused,
#                       so that a wrong path never drops the earlier versions.
#
# Needs the certificate "Developer ID Application" of the team named in
# App/Config/Signing.xcconfig and the private EdDSA key of the updates in the
# keychain; Sparkle's generate_appcast reads the key, the script never does.
#
# The script builds the commit that is checked out, from an export of it, and
# refuses to run while the working tree has changes. It builds the app in the
# Release configuration with the Hardened Runtime and a secure timestamp; signs
# the parts of Sparkle from the inside out and then the app; checks the
# signatures and asks Gatekeeper; notarizes the app and staples the ticket to
# it; packs it as Seamerge-<version>.zip and as a signed, notarized and stapled
# Seamerge-<version>.dmg; and writes appcast.xml with the zip, signed with the
# EdDSA key, and the section of the version in CHANGELOG.md as release notes.
# Every run starts from a clean build and replaces the results of an earlier
# run of the same version. The results and the logs are in
# .build/release/<version>/. Uploading them is left to the user.

set -euo pipefail

usage() {
  echo "usage: Scripts/release.sh <keychain-profile> [--site <folder> [--new-feed]]" >&2
  exit 2
}

site=""
new_feed=false
case $# in
  1) ;;
  3) [ "$2" = --site ] || usage ;;
  4) [ "$2" = --site ] && [ "$4" = --new-feed ] || usage ;;
  *) usage ;;
esac
profile=$1
[ -n "$profile" ] || usage
if [ $# -ge 3 ]; then
  site=$3
  [ $# -eq 4 ] && new_feed=true
fi

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [ -n "$site" ] && [ ! -d "$site" ]; then
  echo "error: $site is not a folder" >&2
  exit 1
fi
if [ -n "$site" ] && [ ! -f "$site/appcast.xml" ] && ! $new_feed; then
  echo "error: $site has no appcast.xml; check the path, or pass --new-feed to start a new feed there" >&2
  exit 1
fi
if [ -n "$site" ] && [ -f "$site/appcast.xml" ] && $new_feed; then
  echo "error: $site has an appcast.xml already; leave out --new-feed to build on it" >&2
  exit 1
fi

setting() {
  sed -n "s/^$1 = //p" "$2"
}
version=$(setting MARKETING_VERSION App/Config/Version.xcconfig)
team=$(setting DEVELOPMENT_TEAM App/Config/Signing.xcconfig)
if [ -z "$version" ] || [ -z "$team" ]; then
  echo "error: no version in Version.xcconfig or no team in Signing.xcconfig" >&2
  exit 1
fi

# An app without a valid public key of the updates would accept no update.
public_key=$(plutil -extract SUPublicEDKey raw App/Config/Info.plist 2> /dev/null || true)
key_length=$(printf '%s' "$public_key" | base64 -d 2> /dev/null | wc -c | tr -d ' ')
if [ "$key_length" != 32 ]; then
  echo "error: SUPublicEDKey in App/Config/Info.plist is no real key; enter the public key that Sparkle's generate_keys prints" >&2
  exit 1
fi
feed=$(plutil -extract SUFeedURL raw App/Config/Info.plist)
if [ -n "$(git status --porcelain)" ]; then
  echo "error: the working tree has changes; the release builds the commit, so commit or remove them first" >&2
  exit 1
fi

notes_section=$(awk -v heading="## [$version]" '
    index($0, heading) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
  ' CHANGELOG.md)
if [ -z "$(printf '%s' "$notes_section" | tr -d '[:space:]')" ]; then
  echo "error: CHANGELOG.md has no section '## [$version]' for the release notes" >&2
  exit 1
fi

out=.build/release/$version
rm -rf "$out"
mkdir -p "$out"
log=$out/release.log
: > "$log"

fail() {
  echo "error: $1; details are in $log" >&2
  exit 1
}

step() {
  echo "$1"
  printf '\n==> %s\n' "$1" >> "$log"
}

step "Checking the certificate of team $team"
identities=$out/identities.txt
security find-identity -v -p codesigning > "$identities"
identity=$(sed -n "s/.*\"\(Developer ID Application: .* ($team)\)\"/\1/p" "$identities" | head -1)
[ -n "$identity" ] || fail "no valid Developer ID Application certificate of team $team"
echo "$identity" >> "$log"

step "Checking that codesign may use the key of the certificate"
probe=$out/codesign-probe
cp /usr/bin/true "$probe"
codesign --force --sign "$identity" --timestamp=none "$probe" >> "$log" 2>&1 \
  || fail "codesign may not use the key; unlock the login keychain, or run the script in Terminal once and allow codesign to use the key"
rm "$probe"

commit=$(git rev-parse HEAD)
step "Exporting commit ${commit:0:12}"
source=$out/source
mkdir "$source"
git archive --format=tar "$commit" | tar -x -C "$source" || fail "the commit could not be exported"

# Packages come from a cache of the repository, and the keychain is never asked
# for credentials of GitHub, so that no dialog stops the build.
step "Building Seamerge $version"
xcodebuild -project "$source/App/Seamerge.xcodeproj" -scheme Seamerge -configuration Release \
  -derivedDataPath "$out/DerivedData" -packageCachePath "$root/.build/package-cache" \
  -packageAuthorizationProvider netrc -onlyUsePackageVersionsFromResolvedFile \
  -xcconfig "$source/App/Config/Signing.xcconfig" CODE_SIGN_IDENTITY="$identity" \
  clean build >> "$log" 2>&1 || fail "the build failed"
app=$out/Seamerge.app
ditto "$out/DerivedData/Build/Products/Release/Seamerge.app" "$app"
helper=$app/Contents/Helpers/seamerge
sparkle=$app/Contents/Frameworks/Sparkle.framework
sparkle_version=$sparkle/Versions/B

step "Checking that Sparkle speaks English only"
translations=$(find "$sparkle_version/Resources" -name '*.lproj' ! -name Base.lproj)
[ -z "$translations" ] || fail "Sparkle still holds translations: $translations"

# Notarization needs every program in the app signed with the Developer ID, the
# Hardened Runtime and a timestamp. Each part is signed before the bundle that
# holds it, so that every seal covers signed contents; --deep would sign them
# all alike and lose the entitlements of the downloader.
step "Signing Sparkle and the app"
sign() {
  codesign --force --sign "$identity" --options runtime --timestamp "$@" >> "$log" 2>&1 \
    || fail "${*: -1} could not be signed"
}
sign "$sparkle_version/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle_version/XPCServices/Downloader.xpc"
sign "$sparkle_version/Autoupdate"
sign "$sparkle_version/Updater.app"
sign "$sparkle"
sign --preserve-metadata=entitlements "$app"

step "Checking the signatures"
codesign --verify --deep --strict --verbose=2 "$app" >> "$log" 2>&1 \
  || fail "the signature of the app is not valid"
for code in "$app" "$helper" "$sparkle" "$sparkle_version/Autoupdate" \
  "$sparkle_version/Updater.app" "$sparkle_version/XPCServices/Installer.xpc" \
  "$sparkle_version/XPCServices/Downloader.xpc"; do
  details=$out/codesign.txt
  codesign --display --verbose=2 "$code" > "$details" 2>&1
  cat "$details" >> "$log"
  grep -q "^TeamIdentifier=$team$" "$details" || fail "$code is not signed by team $team"
  grep -q "^Timestamp=" "$details" || fail "$code has no secure timestamp"
  grep -Eq "flags=.*runtime" "$details" || fail "$code does not use the Hardened Runtime"
done

step "Asking Gatekeeper before notarization"
assessment=$out/spctl.txt
spctl --assess --type execute -vv "$app" > "$assessment" 2>&1 || true
cat "$assessment" >> "$log"
grep -q "^source=Unnotarized Developer ID$" "$assessment" \
  || fail "Gatekeeper does not see the app as signed with a Developer ID"

# Submits a file for notarization and waits for the answer; on a refusal, the
# log of Apple's check is added to the release log.
notarize() {
  local file=$1 answer=$out/notarization.json
  xcrun notarytool submit "$file" --keychain-profile "$profile" --wait \
    --output-format json > "$answer" 2>> "$log" || true
  cat "$answer" >> "$log"
  local status id
  status=$(plutil -extract status raw "$answer" 2> /dev/null || true)
  if [ "$status" != Accepted ]; then
    id=$(plutil -extract id raw "$answer" 2> /dev/null || true)
    if [ -n "$id" ]; then
      xcrun notarytool log "$id" --keychain-profile "$profile" >> "$log" 2>&1 || true
    fi
    fail "notarization of $(basename "$file") ended with '${status:-no answer}'"
  fi
}

step "Notarizing the app (this takes a few minutes)"
submission=$out/Seamerge-notarization.zip
ditto -c -k --keepParent "$app" "$submission"
notarize "$submission"
rm "$submission"
xcrun stapler staple "$app" >> "$log" 2>&1 || fail "the ticket could not be stapled to the app"

step "Checking the app with Gatekeeper"
spctl --assess --type execute -vv "$app" > "$assessment" 2>&1 || true
cat "$assessment" >> "$log"
grep -q "^source=Notarized Developer ID$" "$assessment" \
  || fail "Gatekeeper does not accept the app as notarized"

step "Packing Seamerge-$version.zip"
zip=$out/Seamerge-$version.zip
ditto -c -k --keepParent "$app" "$zip"

step "Packing, signing and notarizing Seamerge-$version.dmg"
dmg=$out/Seamerge-$version.dmg
staging=$out/dmg
mkdir "$staging"
ditto "$app" "$staging/Seamerge.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Seamerge -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg" \
  >> "$log" 2>&1 || fail "the disk image could not be created"
rm -rf "$staging"
codesign --sign "$identity" --timestamp "$dmg" >> "$log" 2>&1 \
  || fail "the disk image could not be signed"
notarize "$dmg"
xcrun stapler staple "$dmg" >> "$log" 2>&1 || fail "the ticket could not be stapled to the disk image"
spctl --assess --type open --context context:primary-signature -vv "$dmg" > "$assessment" 2>&1 \
  || true
cat "$assessment" >> "$log"
grep -q "^source=Notarized Developer ID$" "$assessment" \
  || fail "Gatekeeper does not accept the disk image as notarized"

# The feed lists the zip at the GitHub release of the version. It builds on the
# current feed, so that it keeps the earlier versions, and holds no deltas.
step "Writing the feed of updates"
updates=$out/updates
mkdir "$updates"
if [ -n "$site" ] && [ -f "$site/appcast.xml" ]; then
  cp "$site/appcast.xml" "$updates/appcast.xml"
elif [ -z "$site" ]; then
  answer=$(curl --silent --show-error --location --output "$updates/appcast.xml" \
    --write-out '%{http_code}' "$feed" 2>> "$log") || fail "the feed $feed could not be fetched"
  case $answer in
    200) ;;
    404) rm "$updates/appcast.xml" ;;
    *) fail "the feed $feed answered with $answer" ;;
  esac
fi
cp "$zip" "$updates/"
printf '%s\n' "$notes_section" > "$updates/Seamerge-$version.md"
generate_appcast=$out/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast
[ -x "$generate_appcast" ] || fail "generate_appcast is missing from the package cache of the build"
appcast_log=$out/generate_appcast.txt
"$generate_appcast" --embed-release-notes --maximum-deltas 0 \
  --download-url-prefix "https://github.com/cykedev/seamerge/releases/download/v$version/" \
  "$updates" > "$appcast_log" 2>&1 || {
  cat "$appcast_log" >> "$log"
  fail "generate_appcast failed"
}
cat "$appcast_log" >> "$log"
if grep -q "does not match" "$appcast_log"; then
  fail "the key in the keychain is not the one whose public key the app holds"
fi
cp "$updates/appcast.xml" "$out/appcast.xml"
if [ -n "$site" ]; then
  cp "$out/appcast.xml" "$site/appcast.xml"
fi

step "Done"
(cd "$out" && shasum -a 256 "Seamerge-$version.zip" "Seamerge-$version.dmg")
echo "The files are in $out/."
if [ -n "$site" ]; then
  echo "The feed is in $site/appcast.xml as well."
fi
