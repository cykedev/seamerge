# shellcheck shell=bash disable=SC2154
# Builds and runs a copy of the app for the scripts that look at it or measure
# it, with the library Probe.swift loaded into it. Sourced, not run; the script
# that sources it sets root, the repository, and bundle_id, the identifier of
# the copy, and calls copy_set_up first.
#
# The copy never takes the place of the installed app: its identifier starts
# with app.eiden.seamerge. and is none of a part of the app, it has no
# services, does not look for updates, restores no windows, shows its English
# text, listens for the helper on a socket in its own folder, and it, its
# settings, its saved state and the build are removed from Launch Services and
# from disk afterwards. It is launched in the background, and the library
# keeps every window it makes fully transparent and letting the pointer
# through from the moment it is made, unless the library shows that window
# itself, and ends the copy should it come to the front all the same. The
# copy is launched only once the library is known to load: it is signed ad
# hoc without the hardened runtime, which would ignore DYLD_INSERT_LIBRARIES,
# as the app as shipped does, and the library writes its first line before
# the app runs, or the copy is stopped.

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

progress() {
  local now elapsed
  now=$(date +%s)
  elapsed=$((now - start))
  printf '%s +%d:%02d %s\n' "$(date +%H:%M:%S)" $((elapsed / 60)) $((elapsed % 60)) "$*" >&2
}

# Succeeds if $1 can name the copy: app.eiden.seamerge. and more, in any case,
# but no identifier of a part of the app, whose settings and registrations
# belong to the user.
is_identifier_of_a_copy() {
  local identifier part
  identifier=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case $identifier in
    app.eiden.seamerge..* | app.eiden.seamerge.*[!a-z0-9.-]* | app.eiden.seamerge.*..* | app.eiden.seamerge.*.) return 1 ;;
    app.eiden.seamerge.?*) ;;
    *) return 1 ;;
  esac
  for part in app.eiden.seamerge $(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);.*/\1/p' \
    "$root/App/Seamerge.xcodeproj/project.pbxproj" | tr '[:upper:]' '[:lower:]'); do
    [ "$identifier" = "$part" ] && return 1
  done
  return 0
}

# Checks the identifier and makes the folder for the run, $work, named after
# $1; exits with 2 for an identifier that is not one of a copy.
copy_set_up() {
  if ! is_identifier_of_a_copy "$bundle_id"; then
    echo "the copy needs an identifier of its own under app.eiden.seamerge.: $bundle_id" >&2
    exit 2
  fi
  start=$(date +%s)
  work=$(mktemp -d "${TMPDIR:-/tmp}/seamerge-$1.XXXXXX") || exit 1
  # The path as the processes of the copy show it, without links.
  work=$(cd "$work" && pwd -P) || exit 1
  # A socket path has at most 103 bytes; a longer one leaves the copy without a socket.
  if [ "$(printf '%s' "$work/seamerge.sock" | LC_ALL=C wc -c)" -gt 103 ]; then
    echo "the temporary folder is too long for the socket of the copy: $work" >&2
    rm -rf "$work"
    exit 1
  fi
  copy=$work/Seamerge.app
  built=$work/build/Build/Products/Release/Seamerge.app
  pid=""
  child=""
  keep=${keep:-false}
}

# Runs the command after $1 with its output in the file $1, in the background,
# so that a signal to the script stops it at once rather than once it ends.
copy_run() {
  local log=$1 status
  shift
  "$@" > "$log" 2>&1 &
  child=$!
  wait "$child"
  status=$?
  child=""
  return "$status"
}

# Process $1 and every process below it.
descendants() {
  local process
  echo "$1"
  for process in $(pgrep -P "$1"); do
    descendants "$process"
  done
}

# Makes $work/clone of the commit $1, or of the working tree with its changes
# for an empty $1.
copy_clone() {
  local clone=$work/clone file
  progress "cloning ${1:-the working tree}"
  if [ -n "$1" ]; then
    mkdir -p "$clone"
    git -C "$root" archive "$1" | tar -x -C "$clone" || return 1
  else
    git clone --quiet "$root" "$clone" || return 1
    while IFS= read -r -d '' file; do
      if [ -e "$root/$file" ]; then
        mkdir -p "$clone/$(dirname "$file")"
        cp -p "$root/$file" "$clone/$file"
      else
        rm -f "$clone/$file"
      fi
    done < <(git -C "$root" ls-files -z --modified --others --exclude-standard)
  fi
}

# Sets files to the inputs $@: the files of a case of
# Scripts/measure-large-files.sh for one input, written first with the base of
# a merge, and the inputs themselves otherwise. A comparison has old and new, a
# merge theirs, base and ours, in the order of the fields.
copy_files() {
  local suite=Packages/SeamergeKit/Tests/SeamergeUITests name file
  files=()
  if [ $# -ne 1 ]; then
    files=("$@")
    return 0
  fi
  # The suite always comes from the working tree, so that every commit writes the same files.
  mkdir -p "$work/clone/$suite/Support" "$work/files"
  cp -p "$root/$suite/LargeFileMeasurements.swift" "$work/clone/$suite/"
  cp -p "$root/$suite"/Support/LargeFile*.swift "$work/clone/$suite/Support/"
  progress "writing the files of $1"
  if ! SEAMERGE_MEASURE_CASE=$1 SEAMERGE_MEASURE_FILES=$work/files copy_run "$work/files.log" \
    swift test --package-path "$work/clone/Packages/SeamergeKit" \
    --filter LargeFileMeasurements; then
    echo "the files of $1 could not be written (log: $work/files.log)" >&2
    keep=true
    return 1
  fi
  for name in old new theirs base ours; do
    for file in "$work/files/$name".*; do
      [ -e "$file" ] && files+=("$file")
    done
  done
  return 0
}

# Builds the app of the clone in release mode into $copy with the identifier
# of the copy, and the library into $work/Probe.dylib.
copy_build() {
  local plist=$copy/Contents/Info.plist
  progress "building the app in release mode"
  if ! copy_run "$work/build.log" xcodebuild -project "$work/clone/App/Seamerge.xcodeproj" \
    -scheme Seamerge -configuration Release -destination platform=macOS \
    -derivedDataPath "$work/build" -packageCachePath "$work/package-cache" \
    -packageAuthorizationProvider netrc -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO -quiet build; then
    grep -E 'error:' "$work/build.log" | head -n 20 >&2
    echo "build failed (log: $work/build.log)" >&2
    keep=true
    return 1
  fi
  ditto "$built" "$copy" || return 1
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist" || return 1
  /usr/libexec/PlistBuddy -c "Delete :NSServices" "$plist" 2> /dev/null
  /usr/libexec/PlistBuddy -c "Delete :SUEnableAutomaticChecks" "$plist" 2> /dev/null
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool false" "$plist" || return 1
  codesign --force --deep --sign - "$copy" > "$work/sign.log" 2>&1 || {
    cat "$work/sign.log" >&2
    return 1
  }
  if codesign --display --verbose=2 "$copy" 2>&1 | grep -q '^CodeDirectory.*flags=.*runtime'; then
    echo "the copy has the hardened runtime, which would not load the library" >&2
    return 1
  fi
  # The library always comes from the working tree, so that every commit is driven alike.
  if ! copy_run "$work/probe-build.log" swiftc -O -swift-version 6 -emit-library \
    -module-name SeamergeProbe -Xlinker -init -Xlinker _seamergeProbeStart \
    -o "$work/Probe.dylib" "$root/Scripts/Support/Probe.swift"; then
    cat "$work/probe-build.log" >&2
    return 1
  fi
  codesign --force --sign - "$work/Probe.dylib" > /dev/null 2>&1
}

# Writes the settings of the copy: the arrangement $1, aligned, connected or
# single, and whether the base of a merge is hidden, $2, true or false.
copy_settings() {
  local connects=false single=false
  case $1 in
    connected) connects=true ;;
    single) single=true ;;
  esac
  defaults write "$bundle_id" ConnectsChanges -bool "$connects"
  defaults write "$bundle_id" ShowsSingleColumn -bool "$single"
  defaults write "$bundle_id" HidesBase -bool "$2"
  defaults write "$bundle_id" AppleLanguages -array en
}

# Launches the copy hidden and in the background with $files, the library
# loaded and the variables of the environment $@ for it, SEAMERGE_PROBE_ and
# more, writing its lines to $probe_output, and sets pid.
copy_launch() {
  local variable opening=(-g -j -n -a "$copy" --env "DYLD_INSERT_LIBRARIES=$work/Probe.dylib")
  probe_output=$work/probe.txt
  : > "$probe_output"
  for variable in "SEAMERGE_PROBE_OUTPUT=$probe_output" "$@"; do
    opening+=(--env "$variable")
  done
  open "${opening[@]}" "${files[@]}" --args -SessionSocketDirectory "$work" \
    -ApplePersistenceIgnoreState YES || return 1
  for _ in $(seq 1 30); do
    pid=$(pgrep -f "^$copy/Contents/MacOS/" | head -n 1)
    [ -n "$pid" ] && break
    sleep 1
  done
  [ -n "$pid" ] || { echo "the copy did not start" >&2; return 1; }
  # The library writes its first line as dyld loads it, before the app makes a window.
  for _ in $(seq 1 50); do
    grep -q ' probe loaded$' "$probe_output" && return 0
    sleep 0.1
  done
  copy_quit
  echo "the library did not load into the copy, which was stopped" >&2
  return 1
}

# Waits up to $1 seconds until the library writes a line that matches the
# extended regular expression $2, and fails at once if it fails or the copy
# ends.
copy_wait_for() {
  local tenths=$(($1 * 10))
  for _ in $(seq 1 "$tenths"); do
    grep -Eq "$2" "$probe_output" && return 0
    if grep -q ' failed: ' "$probe_output"; then
      grep ' failed: ' "$probe_output" | sed 's/^[0-9.]* //' >&2
      return 1
    fi
    if ! kill -0 "$pid" 2> /dev/null; then
      echo "the copy ended (lines: $probe_output)" >&2
      keep=true
      return 1
    fi
    sleep 0.1
  done
  echo "the copy did not get that far within $1 s (lines: $probe_output)" >&2
  keep=true
  return 1
}

# Quits the copy and waits until it has, so that its settings can go.
copy_quit() {
  [ -n "$pid" ] || return 0
  kill "$pid" 2> /dev/null
  for _ in $(seq 1 50); do
    kill -0 "$pid" 2> /dev/null || break
    sleep 0.1
  done
  kill -KILL "$pid" 2> /dev/null
  pid=""
}

# Stops what runs, quits the copy, removes it from Launch Services, its
# settings and what macOS keeps under its identifier, and the folder unless it
# is to be kept.
copy_clean_up() {
  local app
  if [ -n "$child" ]; then
    # shellcheck disable=SC2046 # one process identifier a word
    kill -TERM $(descendants "$child") 2> /dev/null
    wait "$child" 2> /dev/null
  fi
  copy_quit
  pkill -f "^$copy/Contents/MacOS/" 2> /dev/null
  # Xcode registers what it builds, under the identifier of the app.
  for app in "$copy" "$built" "$built/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"; do
    [ -d "$app" ] && "$lsregister" -u "$app" 2> /dev/null
  done
  defaults delete "$bundle_id" > /dev/null 2>&1
  # What defaults leaves of the domain is an empty file.
  rm -f "$HOME/Library/Preferences/$bundle_id.plist"
  rm -rf "$HOME/Library/Saved Application State/$bundle_id.savedState" \
    "$HOME/Library/Caches/$bundle_id" "$HOME/Library/HTTPStorages/$bundle_id" \
    "$HOME/Library/HTTPStorages/$bundle_id.binarycookies"
  rm -f "$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/$(printf '%s' "$bundle_id" | tr '[:upper:]' '[:lower:]')".sfl*
  # A copy or build left on disk would be registered again by whatever looks at it next.
  rm -rf "$copy" "$work/build"
  if $keep; then
    progress "kept $work"
  else
    rm -rf "$work"
  fi
}
