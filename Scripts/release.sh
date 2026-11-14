#!/bin/bash
#
# Builds, signs and notarizes a release of Seamerge and packs it for download.
#
# Usage: Scripts/release.sh <keychain-profile>
#
#   <keychain-profile>  The profile that `xcrun notarytool store-credentials`
#                       saved in the keychain; the script reads only its name.
#
# Needs the certificate "Developer ID Application" of the team named in
# App/Config/Signing.xcconfig in the keychain. The script builds the app in the
# Release configuration with that certificate, the Hardened Runtime and a
# secure timestamp, the helper inside it included; checks the signatures;
# notarizes the app and staples the ticket to it; checks it with Gatekeeper;
# and packs it as Seamerge-<version>.zip and as a signed, notarized and stapled
# Seamerge-<version>.dmg. Every run starts from a clean build and replaces the
# results of an earlier run of the same version. The results and the logs are
# in .build/release/<version>/.

set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: Scripts/release.sh <keychain-profile>" >&2
  exit 2
fi
profile=$1

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

setting() {
  sed -n "s/^$1 = //p" "$2"
}
version=$(setting MARKETING_VERSION App/Config/Version.xcconfig)
team=$(setting DEVELOPMENT_TEAM App/Config/Signing.xcconfig)
if [ -z "$version" ] || [ -z "$team" ]; then
  echo "error: no version in Version.xcconfig or no team in Signing.xcconfig" >&2
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

step "Building Seamerge $version"
xcodebuild -project App/Seamerge.xcodeproj -scheme Seamerge -configuration Release \
  -derivedDataPath "$out/DerivedData" -xcconfig App/Config/Signing.xcconfig \
  CODE_SIGN_IDENTITY="$identity" clean build >> "$log" 2>&1 || fail "the build failed"
app=$out/Seamerge.app
ditto "$out/DerivedData/Build/Products/Release/Seamerge.app" "$app"
helper=$app/Contents/Helpers/seamerge

step "Checking the signatures"
codesign --verify --deep --strict --verbose=2 "$app" >> "$log" 2>&1 \
  || fail "the signature of the app is not valid"
for code in "$app" "$helper"; do
  details=$out/codesign.txt
  codesign --display --verbose=2 "$code" > "$details" 2>&1
  cat "$details" >> "$log"
  grep -q "^TeamIdentifier=$team$" "$details" || fail "$code is not signed by team $team"
  grep -q "^Timestamp=" "$details" || fail "$code has no secure timestamp"
  grep -Eq "flags=.*runtime" "$details" || fail "$code does not use the Hardened Runtime"
done

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
assessment=$out/spctl.txt
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

step "Done"
(cd "$out" && shasum -a 256 "Seamerge-$version.zip" "Seamerge-$version.dmg")
echo "The files are in $out/."
