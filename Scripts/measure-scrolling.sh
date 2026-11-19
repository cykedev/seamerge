#!/bin/bash
#
# Measures scrolling on the screen: builds a copy of the app with a bundle
# identifier of its own, compares two files or merges three in it, and a
# library loaded into the copy opens them, shows the window on a screen
# without activating the copy, and plays flicks of a trackpad with momentum
# over it through events it posts to the copy itself, while it counts the
# frames of the window through the display link of its content view. The
# script prints how many frames came late between the first event of the
# flicks and the end of the glide that AppKit adds after the last one. With
# --instruments, Instruments records the hitches instead of the library
# counting frames. Should the copy come to the front, the library ends it and
# the measurement fails.
#
# The window stands above other windows at the top left of the chosen screen
# for the time of the flicks, about two seconds a flick, lets the pointer
# through to the windows below and never takes the key focus: the person at
# the screen can go on working, and no event reaches another window. With
# --transparent, nobody sees it either; whether its frames are then those of
# a window that can be seen is to be compared once. The copy is described in
# Scripts/Support/test-copy.sh.
#
# Usage: Scripts/measure-scrolling.sh [options] (<case> | <file> [<base>] <file>)
#
#   --arrangement <a>   aligned (default), connected or single.
#   --hides-base        Hide the base pane of a merge.
#   --screen <s>        The screen the window goes to: slow (default), the one
#                       with the lowest frame rate, or fast, with the highest.
#   --transparent       Show the window fully transparent.
#   --flicks <n>        Flicks down and up again (default 6).
#   --bundle-id <id>    The bundle identifier of the copy, app.eiden.seamerge.
#                       and more (default app.eiden.seamerge.measure).
#   --revision <rev>    Build a commit instead of the working tree.
#   --counter           Count frames in the copy (the default).
#   --instruments       Record hitches with Instruments instead of counting
#                       frames in the copy.
#   --sample <file>     When counting, also sample the copy into <file> while
#                       it scrolls, which costs frames of its own.
#   --keep              Keep the trace, the files and the logs; the copy and
#                       the build go, since Launch Services would register
#                       them again.
#
# A case is one of Scripts/measure-large-files.sh; its files are written
# first, with the base of a merge. The screen must be unlocked, and
# Instruments records hitches only while the developer mode of the system is
# on (DevToolsSecurity). Neither way needs the permission to control the
# computer or to record the screen.
#
# Exits with 0 when the frames were measured, with 1 otherwise, and with 2 for
# wrong arguments.

set -u

usage() {
  sed -n '/^# Usage:/,/^# computer or to record the screen/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

arrangement=aligned
flicks=6
bundle_id=app.eiden.seamerge.measure
revision=""
counter=true
sample_file=""
keep=false
hides_base=false
screen=slow
transparent=false
inputs=()
while [ $# -gt 0 ]; do
  case $1 in
    --arrangement) [ $# -ge 2 ] || usage; arrangement=$2; shift 2 ;;
    --flicks) [ $# -ge 2 ] || usage; flicks=$2; shift 2 ;;
    --bundle-id) [ $# -ge 2 ] || usage; bundle_id=$2; shift 2 ;;
    --revision) [ $# -ge 2 ] || usage; revision=$2; shift 2 ;;
    --counter) counter=true; shift ;;
    --instruments) counter=false; shift ;;
    --sample) [ $# -ge 2 ] || usage; sample_file=$2; shift 2 ;;
    --keep) keep=true; shift ;;
    --hides-base) hides_base=true; shift ;;
    --screen) [ $# -ge 2 ] || usage; screen=$2; shift 2 ;;
    --transparent) transparent=true; shift ;;
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
# shellcheck source=Support/test-copy.sh
. "$root/Scripts/Support/test-copy.sh"

if ioreg -n Root -d1 -a | grep -q CGSSessionScreenIsLocked; then
  echo "the screen is locked: scrolling cannot be measured" >&2
  exit 1
fi

if ! $counter && ! DevToolsSecurity -status 2>&1 | grep -q enabled; then
  echo "the developer mode is off: Instruments cannot record hitches; count frames instead" >&2
  exit 1
fi

copy_set_up scrolling
recorder=""
ktrace=""
sampler=""
# Stops the sampler and Instruments and removes the recording Instruments
# keeps in the temporary folder, then quits and removes the copy.
clean_up() {
  [ -z "$sampler" ] || kill "$sampler" 2> /dev/null
  if [ -n "$recorder" ]; then
    kill -INT "$recorder" 2> /dev/null
    sleep 2
    kill -KILL "$recorder" 2> /dev/null
    wait "$recorder" 2> /dev/null
  fi
  [ -z "$ktrace" ] || rm -rf "$ktrace"
  copy_clean_up
}
trap clean_up EXIT
trap 'exit 1' INT TERM HUP

copy_clone "$revision" || exit 1
copy_files "${inputs[@]}" || exit 1
case ${#files[@]} in
  2 | 3) ;;
  *) echo "a measurement on the screen compares two files or merges three" >&2; exit 1 ;;
esac
copy_build || exit 1
copy_settings "$arrangement" "$hides_base"

progress "opening ${files[*]##*/} in the copy, $arrangement"
copy_launch "SEAMERGE_PROBE_FLICKS=$flicks" "SEAMERGE_PROBE_SCREEN=$screen" \
  "SEAMERGE_PROBE_TRANSPARENT=$($transparent && echo 1 || echo 0)" \
  "SEAMERGE_PROBE_COUNT_FRAMES=$($counter && echo 1 || echo 0)" "SEAMERGE_PROBE_GO=$work/go" ||
  exit 1
copy_wait_for 900 ' comparison open: ' || exit 1
seconds=$((flicks * 2 * 2 + 4))

# The lines of the frames and of the flicks, which the library writes as they come.
frames=$probe_output

header() {
  printf '# Scrolling on the screen, %s, %d flicks down and up, %s, %s\n' "$arrangement" \
    "$flicks" "$1" "$(date '+%Y-%m-%d %H:%M')"
  printf '# files: %s, %s screen, base %s\n' "${files[*]##*/}" "$screen" \
    "$($hides_base && echo hidden || echo shown)"
}

# Plays the flicks: the library starts them a second after the file go appears,
# and writes a line with when they began and ended and the frame rate of the
# screen, which flicked takes. Fails if the library ended the copy, as when it
# came to the front.
play_flicks() {
  : > "$work/go"
  copy_wait_for $((seconds + 60)) '^flicks ' || return 1
  copy_wait_for 10 ' done$' || return 1
  flicked=$(grep -m 1 '^flicks ' "$frames")
}

copy_wait_for 60 ' showing the window ' || exit 1
progress "$(grep -m 1 ' showing the window ' "$frames" | sed 's/^[0-9.]* //')"
if $counter; then
  progress "counting frames while playing $flicks flicks down and up"
  if [ -n "$sample_file" ]; then
    sample "$pid" $((flicks * 4)) 1 -mayDie -file "$sample_file" > /dev/null 2>&1 &
    sampler=$!
  fi
  play_flicks || exit 1
  [ -z "$sampler" ] || wait "$sampler"
  sampler=""
  progress "$(grep -m 1 ' the last glide ended ' "$frames" | sed 's/^[0-9.]* //')"
  header "frames counted in the copy"
  # The frames from the first event of the flicks to the end of the last
  # glide: a gap between two frames longer than one and a half frames lost
  # the frames in it, and a gap of more than three frames is a hang over two
  # frames.
  awk -v flicked="$flicked" '
    BEGIN { split(flicked, times, " "); from = times[2]; to = times[3] }
    # The frames have three times each; the other lines of the library are notes.
    NF != 3 || $2 !~ /^[0-9.]+$/ { next }
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
    }' "$frames"
  exit
fi

trace=$work/scrolling.trace
progress "recording $seconds s of hitches while playing $flicks flicks down and up"
# Attached to one process, Instruments never ends its recording; it records all
# of them, and only the hitches of the copy count. It writes the recording
# into a file of its own in the temporary folder, which it keeps after saving
# the trace; the file that appears once it starts is that one.
recordings() {
  find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'instruments*.ktrace' 2> /dev/null | sort
}
recordings > "$work/recordings-before"
xcrun xctrace record --template 'Animation Hitches' --all-processes --time-limit "${seconds}s" \
  --output "$trace" --no-prompt < /dev/null > "$work/record.log" 2>&1 &
recorder=$!
for _ in $(seq 1 50); do
  ktrace=$(recordings | comm -13 "$work/recordings-before" - | head -n 1)
  [ -n "$ktrace" ] && break
  sleep 0.1
done
sleep 1
play_flicks || exit 1
# Saving takes Instruments long, more than a minute for a few seconds of
# recording, and it may still not exit then; ten minutes past its time limit,
# it is stopped either way.
for _ in $(seq 1 $((seconds + 600))); do
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
