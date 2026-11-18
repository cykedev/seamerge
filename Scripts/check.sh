#!/bin/bash
#
# Checks the repository: the format of every Swift file, then build and tests
# of each package under Packages/ and of the Xcode project under App/.
#
# Usage: Scripts/check.sh [--quick]
#
#   --quick  Check format and build only; skip the tests.
#
# Prints one line per step and the errors of failed steps. The full output of
# every step is in .build/check.log. Exits with 0 when every step passed and
# with 1 otherwise.

set -u

usage() {
  echo "usage: Scripts/check.sh [--quick]" >&2
  exit 2
}

quick=false
case $# in
  0) ;;
  1) [ "$1" = --quick ] && quick=true || usage ;;
  *) usage ;;
esac

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

log_dir=.build
log=$log_dir/check.log
mkdir -p "$log_dir"

# Each run writes into a directory of its own and replaces the log only when it
# ends, so that two runs at the same time neither delete nor mix their files.
work=$(mktemp -d "$log_dir/check.XXXXXX") || exit 1
trap 'mv -f "$work/check.log" "$log"; rm -rf "$work"' EXIT
run_log=$work/check.log
step_log=$work/step.log
raw_log=$work/raw.log
: > "$run_log"

failed=0
total=0
max_error_lines=20

# Compiler and linter diagnostics, SwiftPM errors and failed Swift tests. Left
# out: the compiler's summary of a failed command, which repeats the diagnostics
# above it, and the warnings of the vendored Perforce code, which a build from
# scratch always prints and which are accepted. Errors there are still shown.
diagnostic_pattern='^[^[:space:]].*:[0-9]+:[0-9]+: (error|warning):|^error: |recorded an issue at'
noise_pattern='failed with a nonzero exit code|^error: Build failed|/Vendor/.*: warning:'

# Runs one step, records its output in the log and prints its outcome. The
# remaining arguments are the command; it runs from the repository root. With
# --tests first, the step runs tests and passes only if every test run it
# started ended with a summary that counts at least one test: a run that ends
# early can still exit with 0.
run_step() {
  local runs_tests=false
  if [ "$1" = --tests ]; then
    runs_tests=true
    shift
  fi
  local name=$1 status=0 missing=""
  shift
  total=$((total + 1))
  "$@" > "$raw_log" 2>&1 || status=$?
  strip_escapes < "$raw_log" > "$step_log"
  printf '\n==> %s\n$ %s\n' "$name" "$*" >> "$run_log"
  cat "$step_log" >> "$run_log"
  if [ "$status" -eq 0 ] && $runs_tests; then
    missing=$(missing_test_summary)
  fi
  if [ "$status" -eq 0 ] && [ -z "$missing" ]; then
    printf '%-28s ok%s\n' "$name" "$(test_summary)"
    return 0
  fi
  failed=$((failed + 1))
  printf '%-28s failed\n' "$name"
  if [ -n "$missing" ]; then
    echo "  $missing" | tee -a "$run_log"
  else
    print_errors
  fi
  return 1
}

# Removes the colour and hyperlink escapes the compiler writes even into files.
strip_escapes() {
  LC_ALL=C sed -E $'s/\x1b\\[[0-9;]*m//g; s/\x1b\\]8;;[^\x1b]*\x1b\\\\//g'
}

skip_step() {
  total=$((total + 1))
  printf '%-28s skipped (%s)\n' "$1" "$2"
}

# The number of tests Swift Testing ran, summed over the test targets, if the
# step ran tests.
test_summary() {
  awk '/Test run with [0-9]+ tests? / {
      for (i = 1; i < NF; i++) if ($i == "with") { sum += $(i + 1); found = 1 }
    }
    END { if (found) printf " (%d tests)", sum }' "$step_log"
}

# Says what is missing from the summaries of Swift Testing in the log of a step
# that ran tests, or nothing if every run that started ended with one and they
# count at least one test.
missing_test_summary() {
  awk '/Test run started\./ { started++ }
    /Test run with [0-9]+ tests? / {
      ended++
      for (i = 1; i < NF; i++) if ($i == "with") sum += $(i + 1)
    }
    END {
      if (ended == 0) print "The log has no summary of a test run."
      else if (started > ended) printf "%d of %d test runs ended without a summary.\n", started - ended, started
      else if (sum == 0) print "The test runs counted no tests."
    }' "$step_log"
}

# Prints the diagnostics of the failed step without paths into the repository;
# the log has the rest.
print_errors() {
  local errors count
  errors=$(grep -E "$diagnostic_pattern" "$step_log" | grep -vE "$noise_pattern" |
    sed "s|$root/||g" | awk '!seen[$0]++')
  if [ -z "$errors" ]; then
    errors=$(tail -n 5 "$step_log")
  fi
  count=$(printf '%s\n' "$errors" | wc -l | tr -d ' ')
  printf '%s\n' "$errors" | head -n "$max_error_lines" | sed 's/^/  /'
  if [ "$count" -gt "$max_error_lines" ]; then
    echo "  ... $((count - max_error_lines)) more in $log"
  fi
}

# Every Swift file Git tracks or would track, so that build products and
# ignored files are never linted.
lint_format() {
  local files=() file
  while IFS= read -r -d '' file; do
    [ -f "$file" ] && files+=("$file")
  done < <(git ls-files -z --cached --others --exclude-standard -- '*.swift')
  [ ${#files[@]} -eq 0 ] && return 0
  swift format lint --strict --parallel -- "${files[@]}"
}

# Starts a copy of the built app as a person does and passes if it still runs
# after a few seconds and listens for the helper, so that a crash at launch,
# such as a framework dyld refuses or a failure building the welcome window,
# fails the check. The copy has a bundle identifier of its own and no services,
# so that it touches neither the settings nor the Services menu of an installed
# Seamerge, and it is unregistered and its settings removed afterwards.
#
# Nobody at the screen notices the copy: as an agent app it has no Dock icon,
# and it is launched hidden and in the background, so it neither comes to the
# front nor shows its window. It listens on a socket in its own folder, which
# every run makes anew, so that it leaves the socket of a running Seamerge and
# of another check alone; the path takes 93 of the 104 bytes a socket path may
# have.
launch_app() {
  local built=$1 identifier=app.eiden.seamerge.check folder copy pid
  local launched=false alive=false listens=false
  [ -d "$built" ] || { echo "no app at $built"; return 1; }
  # The resolved path, as the process of the copy has it, finds the process.
  folder=$(mktemp -d "${TMPDIR:-/tmp}/seamerge-launch.XXXXXX") || return 1
  folder=$(realpath "$folder") || return 1
  copy=$folder/Seamerge.app
  if ditto "$built" "$copy" &&
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $identifier" \
      -c "Delete :NSServices" -c "Add :LSUIElement bool true" "$copy/Contents/Info.plist" &&
    codesign --force --deep --sign - --preserve-metadata=entitlements "$copy" &&
    open -g -j -n "$copy" --args -SessionSocketDirectory "$folder" \
      -SUEnableAutomaticChecks NO -SUHasLaunchedBefore YES; then
    launched=true
    sleep 3
    pid=$(pgrep -f "^$copy/Contents/MacOS/Seamerge")
    [ -n "$pid" ] && alive=true
    [ -S "$folder/seamerge.sock" ] && listens=true
    if $alive; then
      kill "$pid"
      for _ in {1..20}; do
        kill -0 "$pid" 2> /dev/null || break
        sleep 0.1
      done
    fi
  else
    echo "the copy of the app could not be prepared or launched"
  fi
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$copy" 2> /dev/null
  defaults delete "$identifier" 2> /dev/null
  rm -f "$HOME/Library/Preferences/$identifier.plist"
  rm -rf "$folder"
  $launched || return 1
  $alive || { echo "Seamerge quit within 3 seconds of its launch"; return 1; }
  $listens || { echo "Seamerge did not listen on a socket in $folder"; return 1; }
}

run_step "format" lint_format

for manifest in Packages/*/Package.swift; do
  package=$(dirname "$manifest")
  name=$(basename "$package")
  if run_step "build $name" swift build --package-path "$package" --build-tests \
    --explicit-target-dependency-import-check error; then
    if $quick; then
      :
    elif [ "$name" = SeamergeKit ]; then
      # The window tests share the main actor. One at a time, each of them
      # waits for its own work only, so that its time limit stops a test that
      # hangs rather than one that waits for its turn.
      run_step --tests "test $name" swift test --package-path "$package" \
        --skip-build --skip SeamergeUITests
      run_step --tests "test $name windows" swift test --package-path "$package" \
        --skip-build --filter SeamergeUITests --no-parallel
    else
      run_step --tests "test $name" swift test --package-path "$package" --skip-build
    fi
  elif ! $quick; then
    skip_step "test $name" "build failed"
  fi
done

if [ -d App ]; then
  # Packages come from a cache of the repository, and the keychain is never
  # asked for credentials of GitHub, so that no dialog stops the check.
  xcode=(xcodebuild -project App/Seamerge.xcodeproj -scheme Seamerge
    -destination platform=macOS -derivedDataPath "$log_dir/xcode"
    -packageCachePath "$root/$log_dir/package-cache" -packageAuthorizationProvider netrc
    -onlyUsePackageVersionsFromResolvedFile)
  if $quick; then
    run_step "xcodebuild build" "${xcode[@]}" -quiet build
  else
    # Without -quiet, so that the log has the summary of Swift Testing to count the tests.
    run_step --tests "xcodebuild test" "${xcode[@]}" test
  fi
  run_step "app launches" launch_app "$log_dir/xcode/Build/Products/Debug/Seamerge.app"
fi

if [ "$failed" -eq 0 ]; then
  echo "check passed: $total steps (log: $log)"
  exit 0
fi
echo "check failed: $failed of $total steps (log: $log)"
exit 1
