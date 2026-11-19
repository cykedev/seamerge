#!/bin/bash
#
# Draws the window of a comparison or merge as the app shows it, toolbar,
# headers and panes included, into PNG files, without recording the screen:
# builds a copy of the app, opens the files in it, and a library loaded into
# the copy gives the window its size, appearance and scroll position and draws
# it. Every window of the copy is fully transparent and lets the pointer
# through from the moment it is made, and the library ends the copy should it
# come to the front. Until the picture is drawn, the library also looks at the
# list of windows of the window server every 20 milliseconds, and the script
# fails, without naming the picture on standard output, if a window of the
# copy was on a screen without being transparent or the copy came to the
# front. The copy is described in Scripts/Support/test-copy.sh.
#
# Usage: Scripts/picture-window.sh [options] (<case> | <file> [<base>] <file>)
#
#   --appearance <a>    light (default), dark, light-increased-contrast or
#                       dark-increased-contrast; repeat it for several
#                       pictures, each from a launch of its own.
#   --arrangement <a>   aligned (default), connected or single.
#   --hides-base        Hide the base pane of a merge.
#   --size <s>          The size of the content of the window: min, the least
#                       the window allows, or <width>x<height> in points; by
#                       default the size the window opens at.
#   --scroll <f>        Scroll the larger pane to the fraction <f> of how far
#                       it scrolls, from 0 to 1, before drawing.
#   --name <n>          The first part of the names of the pictures (default:
#                       the case, or the name of the last file).
#   --out <folder>      Where the pictures go (default:
#                       $TMPDIR/SeamergePictures/Window).
#   --bundle-id <id>    The bundle identifier of the copy, app.eiden.seamerge.
#                       and more (default app.eiden.seamerge.picture).
#   --revision <rev>    Build a commit instead of the working tree.
#   --keep              Keep the files and the logs.
#
# A case is one of Scripts/measure-large-files.sh. A picture is named
# <name>-<arrangement>-<appearance>.png, with -<size> before .png for --size;
# its path goes to standard output, the progress to standard error.
#
# The window draws its focus as the key window does. What the picture shows
# differs from the screen where the window server draws rather than the
# window: glass and other translucent surfaces show without what lies behind
# them, the window has neither its rounded corners nor its shadow, and the
# buttons of its title bar are gray, as in an app that is not active. With
# increased contrast, only the colors of the app change, not those of the
# system.
#
# Exits with 0 when every picture was drawn while no window could be seen,
# with 1 otherwise, and with 2 for wrong arguments.

set -u

usage() {
  sed -n '/^# Usage:/,/^#   --keep/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

appearances=()
arrangement=aligned
hides_base=false
size=""
scroll=""
name=""
out=${TMPDIR:-/tmp}/SeamergePictures/Window
bundle_id=app.eiden.seamerge.picture
revision=""
keep=false
inputs=()
while [ $# -gt 0 ]; do
  case $1 in
    --appearance) [ $# -ge 2 ] || usage; appearances+=("$2"); shift 2 ;;
    --arrangement) [ $# -ge 2 ] || usage; arrangement=$2; shift 2 ;;
    --hides-base) hides_base=true; shift ;;
    --size) [ $# -ge 2 ] || usage; size=$2; shift 2 ;;
    --scroll) [ $# -ge 2 ] || usage; scroll=$2; shift 2 ;;
    --name) [ $# -ge 2 ] || usage; name=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; out=$2; shift 2 ;;
    --bundle-id) [ $# -ge 2 ] || usage; bundle_id=$2; shift 2 ;;
    --revision) [ $# -ge 2 ] || usage; revision=$2; shift 2 ;;
    --keep) keep=true; shift ;;
    -*) usage ;;
    *) inputs+=("$1"); shift ;;
  esac
done
[ ${#appearances[@]} -gt 0 ] || appearances=(light)
for appearance in "${appearances[@]}"; do
  case $appearance in
    light | dark | light-increased-contrast | dark-increased-contrast) ;;
    *) usage ;;
  esac
done
case $arrangement in aligned | connected | single) ;; *) usage ;; esac
[[ -z $size || $size == min || $size =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]] || usage
[[ -z $scroll || $scroll =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]] || usage
case ${#inputs[@]} in 1 | 2 | 3) ;; *) usage ;; esac
if [ -z "$name" ]; then
  name=$(basename "${inputs[${#inputs[@]} - 1]}")
  name=${name%.*}
fi
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$out" || exit 1
out=$(cd "$out" && pwd -P) || exit 1
# shellcheck source=Support/test-copy.sh
. "$root/Scripts/Support/test-copy.sh"

copy_set_up picture
trap copy_clean_up EXIT
trap 'exit 1' INT TERM HUP

copy_clone "$revision" || exit 1
copy_files "${inputs[@]}" || exit 1
case ${#files[@]} in
  2 | 3) ;;
  *) echo "a picture shows the comparison of two files or the merge of three" >&2; exit 1 ;;
esac
copy_build || exit 1
copy_settings "$arrangement" "$hides_base"

failed=false
for appearance in "${appearances[@]}"; do
  picture=$out/$name-$arrangement-$appearance${size:+-$size}.png
  rm -f "$picture"
  progress "drawing ${files[*]##*/}, $arrangement, $appearance"
  variables=("SEAMERGE_PROBE_PICTURE=$picture" "SEAMERGE_PROBE_APPEARANCE=$appearance")
  [ -n "$size" ] && variables+=("SEAMERGE_PROBE_SIZE=$size")
  [ -n "$scroll" ] && variables+=("SEAMERGE_PROBE_SCROLL=$scroll")
  if copy_launch "${variables[@]}" && copy_wait_for 900 ' done$'; then
    copy_quit
    # The library notes the state of each window of the copy as it first sees it and each
    # time it changes; it ends the copy if the copy comes to the front.
    shown=$(grep -E 'on screen true, alpha (0[.][0-9]*[1-9]|[1-9])|failed:' "$probe_output")
    if [ -n "$shown" ]; then
      echo "a window of the copy could be seen; the picture is not to be used: $picture" >&2
      printf '%s\n' "$shown" | sed 's/^[0-9.]* //' >&2
      failed=true
    else
      progress "no window could be seen, the copy never came to the front" \
        "($(grep -c 'screen check: window' "$probe_output") states of windows," \
        "$(grep -Eo '[0-9]+ checks' "$probe_output" | tail -n 1))"
      echo "$picture"
    fi
  else
    failed=true
    copy_quit
  fi
  $keep && cp "$probe_output" "$out/$name-$arrangement-$appearance${size:+-$size}.txt"
done
$failed && exit 1
exit 0
