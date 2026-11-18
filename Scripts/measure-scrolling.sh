#!/bin/bash
#
# Measures scrolling on the screen: builds a copy of the app with a bundle
# identifier of its own, compares two files or merges three in it from the
# sheet Compare Files or Merge Files, plays flicks of a trackpad with momentum
# over the window while Instruments records hitches, and prints how many frames
# came late. With
# --counter, a library loaded into the copy counts the frames of the window
# instead, through the display link of its content view, without Instruments.
# The copy never takes the place of the installed app: its identifier starts
# with app.eiden.seamerge. and is none of a part of the app, it has no
# services, does not look for updates, shows its English text, and it, its
# settings, its saved state and the build are removed from Launch Services
# and from disk afterwards. The library loads only into this copy, which is
# signed ad hoc without the hardened runtime; the app as shipped runs with the
# hardened runtime, which ignores DYLD_INSERT_LIBRARIES.
#
# Usage: Scripts/measure-scrolling.sh [options] (<case> | <file> [<base>] <file>)
#
#   --arrangement <a>   aligned (default), connected or single.
#   --hides-base        Hide the base pane of a merge.
#   --screen <s>        The screen the window goes to: slow (default), the one
#                       with the lowest frame rate, or fast, with the highest.
#   --flicks <n>        Flicks down and up again (default 6).
#   --bundle-id <id>    The bundle identifier of the copy, app.eiden.seamerge.
#                       and more (default app.eiden.seamerge.measure).
#   --revision <rev>    Build a commit instead of the working tree.
#   --counter           Count frames in the copy instead of recording hitches
#                       with Instruments.
#   --sample <file>     With --counter, also sample the copy into <file> while
#                       it scrolls, which costs frames of its own.
#   --keep              Keep the trace, the files and the logs; the copy and
#                       the build go, since Launch Services would register
#                       them again.
#
# A case is one of Scripts/measure-large-files.sh; its files are written
# first, with the base of a merge. The screen must be unlocked, the process
# that runs the script needs the permission to control the computer, which
# clicking Compare or Merge and posting the scroll events take, and
# Instruments records hitches only while the developer mode of the system is
# on (DevToolsSecurity).
#
# Exits with 0 when the frames were measured, with 1 otherwise, and with 2 for
# wrong arguments.

set -u

usage() {
  sed -n '/^# Usage:/,/^# on (DevToolsSecurity)/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

arrangement=aligned
flicks=6
bundle_id=app.eiden.seamerge.measure
revision=""
counter=false
sample_file=""
keep=false
hides_base=false
screen=slow
inputs=()
while [ $# -gt 0 ]; do
  case $1 in
    --arrangement) [ $# -ge 2 ] || usage; arrangement=$2; shift 2 ;;
    --flicks) [ $# -ge 2 ] || usage; flicks=$2; shift 2 ;;
    --bundle-id) [ $# -ge 2 ] || usage; bundle_id=$2; shift 2 ;;
    --revision) [ $# -ge 2 ] || usage; revision=$2; shift 2 ;;
    --counter) counter=true; shift ;;
    --sample) [ $# -ge 2 ] || usage; sample_file=$2; shift 2 ;;
    --keep) keep=true; shift ;;
    --hides-base) hides_base=true; shift ;;
    --screen) [ $# -ge 2 ] || usage; screen=$2; shift 2 ;;
    -*) usage ;;
    *) inputs+=("$1"); shift ;;
  esac
done
case $arrangement in aligned | connected | single) ;; *) usage ;; esac
case $flicks in '' | *[!0-9]* | 0) usage ;; esac
case ${#inputs[@]} in 1 | 2 | 3) ;; *) usage ;; esac
case $screen in slow | fast) ;; *) usage ;; esac
[ -z "$sample_file" ] || $counter || usage
root=$(cd "$(dirname "$0")/.." && pwd)

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
if ! is_identifier_of_a_copy "$bundle_id"; then
  echo "the copy needs an identifier of its own under app.eiden.seamerge.: $bundle_id" >&2
  exit 2
fi
start=$(date +%s)
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

progress() {
  local now elapsed
  now=$(date +%s)
  elapsed=$((now - start))
  printf '%s +%d:%02d %s\n' "$(date +%H:%M:%S)" $((elapsed / 60)) $((elapsed % 60)) "$*" >&2
}

if ioreg -n Root -d1 -a | grep -q CGSSessionScreenIsLocked; then
  echo "the screen is locked: scrolling cannot be measured" >&2
  exit 1
fi

if ! $counter && ! DevToolsSecurity -status 2>&1 | grep -q enabled; then
  echo "the developer mode is off: Instruments cannot record hitches; try --counter" >&2
  exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/seamerge-scrolling.XXXXXX") || exit 1
# The path as the processes of the copy show it, without links.
work=$(cd "$work" && pwd -P) || exit 1
copy=$work/Seamerge.app
built=$work/build/Build/Products/Release/Seamerge.app
pid=""
recorder=""
# Stops Instruments and quits the copy, removes it from Launch Services, its
# settings and what macOS keeps under its identifier, and the folder unless it
# is to be kept.
clean_up() {
  # The driver first, so that no scroll event reaches another window.
  pkill -f "^$work/driver " 2> /dev/null
  if [ -n "$recorder" ]; then
    kill -INT "$recorder" 2> /dev/null
    sleep 2
    kill -KILL "$recorder" 2> /dev/null
  fi
  if [ -n "$pid" ]; then
    kill "$pid" 2> /dev/null
    # Its settings go only once it no longer writes them.
    for _ in $(seq 1 50); do
      kill -0 "$pid" 2> /dev/null || break
      sleep 0.1
    done
  else
    pkill -f "^$copy/Contents/MacOS/" 2> /dev/null
  fi
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
trap clean_up EXIT
trap 'exit 1' INT TERM HUP

clone=$work/clone
progress "cloning ${revision:-the working tree}"
if [ -n "$revision" ]; then
  mkdir -p "$clone"
  git -C "$root" archive "$revision" | tar -x -C "$clone" || exit 1
else
  git clone --quiet "$root" "$clone" || exit 1
  while IFS= read -r -d '' file; do
    if [ -e "$root/$file" ]; then
      mkdir -p "$clone/$(dirname "$file")"
      cp -p "$root/$file" "$clone/$file"
    else
      rm -f "$clone/$file"
    fi
  done < <(git -C "$root" ls-files -z --modified --others --exclude-standard)
fi

if [ ${#inputs[@]} -eq 1 ]; then
  suite=Packages/SeamergeKit/Tests/SeamergeUITests
  mkdir -p "$clone/$suite/Support"
  cp -p "$root/$suite/LargeFileMeasurements.swift" "$clone/$suite/"
  cp -p "$root/$suite"/Support/LargeFile*.swift "$clone/$suite/Support/"
  progress "writing the files of ${inputs[0]}"
  mkdir -p "$work/files"
  if ! SEAMERGE_MEASURE_CASE=${inputs[0]} SEAMERGE_MEASURE_FILES=$work/files \
    swift test --package-path "$clone/Packages/SeamergeKit" \
    --filter LargeFileMeasurements > "$work/files.log" 2>&1; then
    echo "the files of ${inputs[0]} could not be written (log: $work/files.log)" >&2
    keep=true
    exit 1
  fi
  # A comparison has old and new, a merge theirs, base and ours, in the order of the fields.
  files=()
  for name in old new theirs base ours; do
    for file in "$work/files/$name".*; do
      [ -e "$file" ] && files+=("$file")
    done
  done
else
  files=("${inputs[@]}")
fi
case ${#files[@]} in
  2 | 3) ;;
  *) echo "a measurement on the screen compares two files or merges three" >&2; exit 1 ;;
esac

progress "building the app in release mode"
if ! xcodebuild -project "$clone/App/Seamerge.xcodeproj" -scheme Seamerge -configuration Release \
  -destination platform=macOS -derivedDataPath "$work/build" \
  -packageCachePath "$work/package-cache" -packageAuthorizationProvider netrc \
  -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO -quiet build \
  > "$work/build.log" 2>&1; then
  grep -E 'error:' "$work/build.log" | head -n 20 >&2
  echo "build failed (log: $work/build.log)" >&2
  keep=true
  exit 1
fi
ditto "$built" "$copy" || exit 1
plist=$copy/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist" || exit 1
/usr/libexec/PlistBuddy -c "Delete :NSServices" "$plist" 2> /dev/null
/usr/libexec/PlistBuddy -c "Delete :SUEnableAutomaticChecks" "$plist" 2> /dev/null
/usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool false" "$plist" || exit 1
codesign --force --deep --sign - "$copy" > "$work/sign.log" 2>&1 || {
  cat "$work/sign.log" >&2
  exit 1
}

case $arrangement in
  aligned) connects=false single=false ;;
  connected) connects=true single=false ;;
  single) connects=false single=true ;;
esac
defaults write "$bundle_id" ConnectsChanges -bool "$connects"
defaults write "$bundle_id" ShowsSingleColumn -bool "$single"
defaults write "$bundle_id" HidesBase -bool "$hides_base"
# The driver finds the sheet and the button by their English titles.
defaults write "$bundle_id" AppleLanguages -array en

# Drives the copy as the user does: presses Compare or Merge in the sheet that
# the files fill on the welcome window, through the accessibility of the copy,
# and plays flicks as a trackpad
# sends them, over the larger pane of the comparison: the fingers move for a
# quarter of a second, then the content glides on with momentum for a second
# and a half, at 120 events a second, down and up again. The events go where
# the pointer is, so each flick starts only while a window of the copy is the
# front one at that point.
cat > "$work/Driver.swift" << 'SWIFT'
import AppKit
import ApplicationServices
import QuartzCore

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

func windows(of pid: pid_t) -> [(name: String, frame: CGRect)] {
  let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
  return (all ?? []).compactMap { window in
    guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
      (window[kCGWindowLayer as String] as? Int) == 0,
      let bounds = window[kCGWindowBounds as String] as? NSDictionary,
      let frame = CGRect(dictionaryRepresentation: bounds)
    else { return nil }
    return (window[kCGWindowName as String] as? String ?? "", frame)
  }
}

func frontOwner(at point: CGPoint) -> pid_t? {
  let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
  let front = (all ?? []).first { window in
    guard (window[kCGWindowLayer as String] as? Int) == 0,
      let bounds = window[kCGWindowBounds as String] as? NSDictionary,
      let frame = CGRect(dictionaryRepresentation: bounds)
    else { return false }
    return frame.contains(point)
  }
  return front?[kCGWindowOwnerPID as String] as? pid_t
}

func children(of element: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
  return value as? [AXUIElement] ?? []
}

func button(titled title: String, in element: AXUIElement) -> AXUIElement? {
  var role: CFTypeRef?
  var name: CFTypeRef?
  AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
  AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &name)
  if role as? String == kAXButtonRole, name as? String == title { return element }
  return children(of: element).lazy.compactMap { button(titled: title, in: $0) }.first
}

// The windows that are not the comparison: the welcome window and its sheets.
let setupWindows = ["Welcome", "Compare Files", "Merge Files"]

func pressCompare(in pid: pid_t) {
  let app = AXUIElementCreateApplication(pid)
  guard let compare = button(titled: "Compare", in: app) ?? button(titled: "Merge", in: app) else {
    fail("the sheet of \(pid) has no button Compare or Merge")
  }
  guard AXUIElementPerformAction(compare, kAXPressAction as CFString) == .success else {
    fail("Compare could not be pressed")
  }
}

func post(_ delta: Double, phase: Int64, momentum: Int64, at point: CGPoint) {
  guard
    let event = CGEvent(
      scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(delta.rounded()),
      wheel2: 0, wheel3: 0)
  else { return }
  event.location = point
  event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
  event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
  event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
  event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: delta)
  event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: delta)
  event.post(tap: .cghidEventTap)
  usleep(8_333)
}

func flick(_ count: Int, in pid: pid_t) {
  guard let window = windows(of: pid).filter({ !setupWindows.contains($0.name) })
    .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
  else { fail("no comparison of \(pid) on the screen") }
  let point = CGPoint(x: window.frame.minX + window.frame.width * 0.75, y: window.frame.midY)
  NSRunningApplication(processIdentifier: pid)?.activate()
  usleep(500_000)
  CGWarpMouseCursorPosition(point)
  let start = CACurrentMediaTime()
  for flick in 0..<(2 * count) {
    guard frontOwner(at: point) == pid else { fail("another window lies over the comparison") }
    let direction: Double = flick < count ? -1 : 1
    post(0, phase: 1, momentum: 0, at: point)
    for step in 0..<30 { post(direction * Double(4 + step), phase: 2, momentum: 0, at: point) }
    post(0, phase: 4, momentum: 0, at: point)
    var delta = direction * 34
    post(delta, phase: 0, momentum: 1, at: point)
    for _ in 0..<180 {
      delta *= 0.975
      post(delta, phase: 0, momentum: 2, at: point)
    }
    post(0, phase: 0, momentum: 3, at: point)
    usleep(200_000)
  }
  // On the clock of the display link, so that the frames of the flicks can be told apart, and
  // the frame rate of the screen the comparison is on.
  let height = NSScreen.screens.first?.frame.height ?? 0
  let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: point.x, y: height - point.y)) }
  print("flicks", start, CACurrentMediaTime(), screen?.maximumFramesPerSecond ?? 60)
}

// Moves the comparison to the top left of the screen with the lowest or the highest frame rate,
// at the size it has.
func place(in pid: pid_t, fast: Bool) {
  let screens = NSScreen.screens.sorted { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }
  guard let screen = fast ? screens.last : screens.first, let primary = NSScreen.screens.first
  else { fail("no screen") }
  var value: CFTypeRef?
  AXUIElementCopyAttributeValue(
    AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value)
  for window in value as? [AXUIElement] ?? [] {
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
    guard !setupWindows.contains(title as? String ?? "") else { continue }
    let visible = screen.visibleFrame
    var origin = CGPoint(x: visible.minX + 20, y: primary.frame.height - visible.maxY + 20)
    guard let position = AXValueCreate(.cgPoint, &origin),
      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success
    else { fail("the comparison could not be moved") }
  }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3, let pid = pid_t(arguments[2]) else { fail("usage: driver <command> <pid> …") }
switch arguments[1] {
case "compare": pressCompare(in: pid)
case "flicks": flick(arguments.count > 3 ? Int(arguments[3]) ?? 1 : 1, in: pid)
case "windows": for window in windows(of: pid) { print(window.name) }
case "place": place(in: pid, fast: arguments.count > 3 && arguments[3] == "fast")
default: fail("unknown command \(arguments[1])")
}
SWIFT
swiftc -O -o "$work/driver" "$work/Driver.swift" > "$work/driver-build.log" 2>&1 || {
  cat "$work/driver-build.log" >&2
  exit 1
}

# Waits up to 30 seconds until the copy shows a window whose title matches the
# extended regular expression $1, or one that does not with --other.
wait_for_window() {
  local other=false
  [ "$1" = --other ] && other=true && shift
  for _ in $(seq 1 30); do
    if $other; then
      "$work/driver" windows "$pid" | grep -Eqvx "$1" && return 0
    else
      "$work/driver" windows "$pid" | grep -Eqx "$1" && return 0
    fi
    sleep 1
  done
  return 1
}

opening=(-n -a "$copy")
if $counter; then
  # Counts the frames of the key window: each time the display link of its
  # content view fires, a line with the time of the frame, the time of the
  # next one and the time now. A frame the main thread is too busy for never
  # fires. The library takes itself out of the environment, so that the
  # processes the copy starts do not load it.
  cat > "$work/FrameCounter.m" << 'OBJC'
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

@interface SMFrameCounter : NSObject
@property(nonatomic) FILE *output;
@property(nonatomic, strong) CADisplayLink *link;
@end

@implementation SMFrameCounter
- (void)frame:(CADisplayLink *)link {
  fprintf(self.output, "%.6f %.6f %.6f\n", link.timestamp, link.targetTimestamp,
          CACurrentMediaTime());
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
  NSWindow *window = notification.object;
  if (window.isKeyWindow) [self windowDidBecomeKey:notification];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  NSWindow *window = notification.object;
  [self.link invalidate];
  self.link = [window.contentView displayLinkWithTarget:self selector:@selector(frame:)];
  // On a screen whose rate varies, as with ProMotion, the link asks for the highest one, which
  // scrolling gets from the system anyway; otherwise it would count at 60 Hz.
  float highest = (float)window.screen.maximumFramesPerSecond;
  self.link.preferredFrameRateRange = CAFrameRateRangeMake(highest, highest, highest);
  [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  fprintf(self.output, "# window %s\n", window.title.UTF8String);
}
@end

__attribute__((constructor)) static void startCounting(void) {
  const char *path = getenv("SEAMERGE_FRAMES_OUTPUT");
  unsetenv("DYLD_INSERT_LIBRARIES");
  unsetenv("SEAMERGE_FRAMES_OUTPUT");
  if (path == NULL) return;
  static SMFrameCounter *counter;
  counter = [SMFrameCounter new];
  counter.output = fopen(path, "w");
  if (counter.output == NULL) return;
  setvbuf(counter.output, NULL, _IOLBF, 0);
  [NSNotificationCenter.defaultCenter addObserver:counter
                                         selector:@selector(windowDidBecomeKey:)
                                             name:NSWindowDidBecomeKeyNotification
                                           object:nil];
  [NSNotificationCenter.defaultCenter addObserver:counter
                                         selector:@selector(windowDidChangeScreen:)
                                             name:NSWindowDidChangeScreenNotification
                                           object:nil];
}
OBJC
  clang -dynamiclib -fobjc-arc -O2 -framework AppKit -framework QuartzCore \
    -o "$work/FrameCounter.dylib" "$work/FrameCounter.m" > "$work/counter-build.log" 2>&1 || {
    cat "$work/counter-build.log" >&2
    exit 1
  }
  codesign --force --sign - "$work/FrameCounter.dylib" > /dev/null 2>&1 || exit 1
  opening+=(--env "DYLD_INSERT_LIBRARIES=$work/FrameCounter.dylib"
    --env "SEAMERGE_FRAMES_OUTPUT=$work/frames.txt")
fi

progress "opening ${files[*]##*/} in the copy, $arrangement"
open "${opening[@]}" "${files[@]}" || exit 1
for _ in $(seq 1 30); do
  pid=$(pgrep -f "^$copy/Contents/MacOS/" | head -n 1)
  [ -n "$pid" ] && break
  sleep 1
done
[ -n "$pid" ] || { echo "the copy did not start" >&2; exit 1; }
# The sheet is no window of its own on the screen, so press its default button
# as soon as the accessibility of the copy shows it.
pressed=false
for _ in $(seq 1 30); do
  "$work/driver" compare "$pid" 2> /dev/null && pressed=true && break
  sleep 1
done
$pressed || { echo "the copy shows no sheet of files" >&2; exit 1; }
wait_for_window --other "Welcome|Compare Files|Merge Files" || { echo "the comparison did not open" >&2; exit 1; }
sleep 1
"$work/driver" place "$pid" "$screen" || exit 1

header() {
  printf '# Scrolling on the screen, %s, %d flicks down and up, %s, %s\n' "$arrangement" \
    "$flicks" "$1" "$(date '+%Y-%m-%d %H:%M')"
  printf '# files: %s, %s screen, base %s\n' "${files[*]##*/}" "$screen" \
    "$($hides_base && echo hidden || echo shown)"
}

if $counter; then
  progress "counting frames while playing $flicks flicks down and up"
  sleep 1
  sampler=""
  if [ -n "$sample_file" ]; then
    sample "$pid" $((flicks * 4)) 1 -mayDie -file "$sample_file" > /dev/null 2>&1 &
    sampler=$!
  fi
  flicked=$("$work/driver" flicks "$pid" "$flicks") || exit 1
  [ -z "$sampler" ] || wait "$sampler"
  header "frames counted in the copy"
  # The frames between the first and the last event of the flicks: a gap
  # between two frames longer than one and a half frames lost the frames in
  # it, and a gap of more than three frames is a hang over two frames.
  awk -v flicked="$flicked" '
    BEGIN { split(flicked, times, " "); from = times[2]; to = times[3] }
    /^#/ { next }
    $1 >= from && $1 <= to {
      if (count > 0) {
        gap = $1 - last
        gaps[++gapCount] = gap
      }
      last = $1
      count++
    }
    END {
      if (gapCount == 0) { print "no frames during the flicks"; exit 1 }
      for (i = 1; i <= gapCount; i++) sorted[i] = gaps[i]
      for (i = 2; i <= gapCount; i++) {
        v = sorted[i]
        for (j = i - 1; j >= 1 && sorted[j] > v; j--) sorted[j + 1] = sorted[j]
        sorted[j + 1] = v
      }
      frame = sorted[int(gapCount / 2) + 1]
      for (i = 1; i <= gapCount; i++) {
        if (gaps[i] > 1.5 * frame) missed += int(gaps[i] / frame + 0.5) - 1
        if (gaps[i] > 3 * frame) hangs++
        if (gaps[i] > longest) longest = gaps[i]
      }
      printf "refresh-rate %.0f Hz\nframes %d\nmissed-frames %d\nmissed-percent %.2f\n", \
        1 / frame, count + missed, missed, 100 * missed / (count + missed)
      printf "longest-gap %.1f ms\nhangs-over-two-frames %d\n", longest * 1000, hangs + 0
    }' "$work/frames.txt"
  exit
fi

seconds=$((flicks * 2 * 2 + 4))
trace=$work/scrolling.trace
progress "recording $seconds s of hitches while playing $flicks flicks down and up"
# Attached to one process, Instruments never ends its recording; it records all
# of them, and only the hitches of the copy count.
xcrun xctrace record --template 'Animation Hitches' --all-processes --time-limit "${seconds}s" \
  --output "$trace" --no-prompt < /dev/null > "$work/record.log" 2>&1 &
recorder=$!
sleep 2
flicked=$("$work/driver" flicks "$pid" "$flicks") || { kill "$recorder" 2> /dev/null; exit 1; }
echo "$flicked" > "$work/flicks.txt"
# Once it has saved the trace, Instruments may still not exit; two minutes past
# its time limit, it is stopped either way.
for _ in $(seq 1 $((seconds + 120))); do
  kill -0 "$recorder" 2> /dev/null || break
  grep -q "Output file saved" "$work/record.log" && break
  sleep 1
done
kill -INT "$recorder" 2> /dev/null
for _ in $(seq 1 10); do
  kill -0 "$recorder" 2> /dev/null || break
  sleep 1
done
kill -KILL "$recorder" 2> /dev/null
wait "$recorder" 2> /dev/null
recorder=""
if ! grep -q "Output file saved" "$work/record.log"; then
  tail -n 5 "$work/record.log" >&2
  echo "Instruments did not save its recording" >&2
  keep=true
  exit 1
fi

progress "reading the trace"
xcrun xctrace export --input "$trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches"]' > "$work/hitches.xml" \
  2> "$work/export.log" || {
  cat "$work/export.log" >&2
  exit 1
}

header "hitches recorded by Instruments"
# Each row of the hitches table is a frame that came late, with the process
# and by how much in nanoseconds. A value that occurred before refers to it by
# its id. A hitch of d is round(d / frame) missed frames, at least one; the
# frames are the time of the flicks at the rate of the screen. Hitches of the
# system are counted apart.
awk -v pid="$pid" -v flicked="$flicked" '
  function value(element, row,    text, id) {
    if (match(row, "<" element " ref=\"[0-9]+\"")) {
      id = substr(row, RSTART, RLENGTH)
      gsub(/[^0-9]/, "", id)
      return known[element, id]
    }
    if (!match(row, "<" element " id=\"[0-9]+\" fmt=\"[^\"]*\">[^<]*")) return ""
    text = substr(row, RSTART, RLENGTH)
    id = text
    sub(/^[^"]*"/, "", id)
    sub(/".*/, "", id)
    if (element == "process") {
      sub(/^.* fmt="/, "", text)
      sub(/".*/, "", text)
    } else {
      sub(/.*>/, "", text)
    }
    known[element, id] = text
    return text
  }
  BEGIN {
    split(flicked, times, " ")
    frame = 1e9 / times[4]
    frames = (times[3] - times[2]) * times[4]
  }
  /<row>/ {
    duration = value("duration", $0)
    process = value("process", $0)
    # A hitch of the system itself, as of the compositor, names no process.
    if (process == "" && index($0, "<sentinel/>") > 0) systemHitches++
    if (index(process, "(" pid ")") == 0) next
    hitches++
    lost = int(duration / frame + 0.5)
    missed += lost < 1 ? 1 : lost
    if (duration > 2 * frame) hangs++
    if (duration > longest) longest = duration
  }
  END {
    printf "refresh-rate %d Hz\nframes %d\nhitches %d\nmissed-frames %d\n", times[4], frames, \
      hitches, missed
    printf "missed-percent %.2f\nlongest-hitch %.1f ms\nhangs-over-two-frames %d\n", \
      (frames > 0 ? 100 * missed / frames : 0), longest / 1e6, hangs + 0
    printf "system-hitches %d\n", systemHitches + 0
  }' "$work/hitches.xml"
