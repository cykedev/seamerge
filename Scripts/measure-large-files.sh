#!/bin/bash
#
# Measures how the app handles large files: builds the package in release
# mode in a fresh clone, runs the suite LargeFileMeasurements once per case
# and run, each in a process of its own, and prints a table with the median
# and the 95th percentile of every metric.
#
# Usage: Scripts/measure-large-files.sh [options] [case...]
#
#   --revision <rev>    Measure a commit instead of the working tree. The
#                       suite always comes from the working tree, so that two
#                       revisions are measured alike.
#   --runs <n>          Runs per case (default 3).
#   --timeout <min>     Stop a run after this many minutes (default 30); the
#                       table keeps what it measured until then.
#   --compare <file>    Compare with an earlier output of this script: adds
#                       the median from there and the change, marked with !
#                       beyond 15 %.
#   --keep              Keep the clone, the logs and the raw values.
#
# Cases: small-10k large-10k small-100k large-100k small-500k large-500k
# long-5k oneline-2mb big big-500k; without a case, all of them.
#
# The table goes to standard output, the progress with the time of day to
# standard error. Every row has the time of day and the time since the start
# at which its first value was measured, to tell an outlier that another
# process caused. Times are in milliseconds until the window is laid out;
# metrics ending in -drawn include drawing the whole window.
#
# Exits with 0 when every run ended, with 1 when one was stopped or failed,
# and with 2 for wrong arguments.

set -u

all_cases=(small-10k large-10k small-100k large-100k small-500k large-500k long-5k oneline-2mb
  big big-500k)

usage() {
  sed -n '8,23p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

revision=""
runs=3
timeout_minutes=30
compare=""
keep=false
cases=()
while [ $# -gt 0 ]; do
  case $1 in
    --revision) [ $# -ge 2 ] || usage; revision=$2; shift 2 ;;
    --runs) [ $# -ge 2 ] || usage; runs=$2; shift 2 ;;
    --timeout) [ $# -ge 2 ] || usage; timeout_minutes=$2; shift 2 ;;
    --compare) [ $# -ge 2 ] || usage; compare=$2; shift 2 ;;
    --keep) keep=true; shift ;;
    -*) usage ;;
    *)
      case " ${all_cases[*]} " in
        *" $1 "*) cases+=("$1") ;;
        *) echo "unknown case: $1" >&2; usage ;;
      esac
      shift
      ;;
  esac
done
[ ${#cases[@]} -gt 0 ] || cases=("${all_cases[@]}")
case $runs in '' | *[!0-9]* | 0) usage ;; esac
case $timeout_minutes in '' | *[!0-9]* | 0) usage ;; esac
if [ -n "$compare" ] && [ ! -r "$compare" ]; then
  echo "cannot read $compare" >&2
  exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
suite=Packages/SeamergeKit/Tests/SeamergeUITests
start=$(date +%s)

progress() {
  local now elapsed
  now=$(date +%s)
  elapsed=$((now - start))
  printf '%s +%d:%02d %s\n' "$(date +%H:%M:%S)" $((elapsed / 60)) $((elapsed % 60)) "$*" >&2
}

work=$(mktemp -d "${TMPDIR:-/tmp}/seamerge-measure.XXXXXX") || exit 1
# Stops process $1 and every process below it, which swift test starts in a
# process group of their own: asks them to end, and after five seconds ends
# those that are left.
stop() {
  local tree process alive
  tree=$(descendants "$1")
  kill -TERM $tree 2> /dev/null
  for _ in 1 2 3 4 5; do
    alive=false
    for process in $tree; do
      kill -0 "$process" 2> /dev/null && alive=true
    done
    $alive || return 0
    sleep 1
  done
  kill -KILL $tree 2> /dev/null
}

# Process $1 and every process below it.
descendants() {
  local child
  echo "$1"
  for child in $(pgrep -P "$1"); do
    descendants "$child"
  done
}

# A run under way stops with the script, and the folder goes when the script
# ends, unless it is to be kept or a build failed, whose log it holds.
running=""
clean_up() {
  if [ -n "$running" ]; then
    stop "$running"
  fi
  if $keep; then
    progress "kept $work"
  else
    rm -rf "$work"
  fi
}
trap clean_up EXIT
trap 'exit 1' INT TERM HUP
clone=$work/clone
mkdir -p "$work/logs" "$work/values"

progress "cloning ${revision:-the working tree}"
if [ -n "$revision" ]; then
  mkdir -p "$clone"
  git -C "$root" archive "$revision" | tar -x -C "$clone" || exit 1
  measured="$(git -C "$root" rev-parse --short "$revision") ($revision)"
else
  git clone --quiet "$root" "$clone" || exit 1
  # The changes of the working tree, tracked or new, so that work in progress
  # is measured as it stands.
  while IFS= read -r -d '' file; do
    if [ -e "$root/$file" ]; then
      mkdir -p "$clone/$(dirname "$file")"
      cp -p "$root/$file" "$clone/$file"
    else
      rm -f "$clone/$file"
    fi
  done < <(git -C "$root" ls-files -z --modified --others --exclude-standard)
  measured="$(git -C "$root" rev-parse --short HEAD) with the working tree"
fi
mkdir -p "$clone/$suite/Support"
cp -p "$root/$suite/LargeFileMeasurements.swift" "$clone/$suite/"
cp -p "$root/$suite"/Support/LargeFile*.swift "$clone/$suite/Support/"

package=$clone/Packages/SeamergeKit
build=(-c release -Xswiftc -enable-testing --package-path "$package")
progress "building $measured in release mode"
if ! swift build "${build[@]}" --build-tests > "$work/logs/build.log" 2>&1; then
  grep -E 'error:' "$work/logs/build.log" | head -n 20 >&2
  echo "build failed (log: $work/logs/build.log)" >&2
  keep=true
  exit 1
fi

# Runs one case once into the file of values $2; a run past the time limit is
# stopped with every process it started. Sets outcome to how it ended.
run_case() {
  local name=$1 values=$2 log=$3 deadline status
  deadline=$(($(date +%s) + timeout_minutes * 60))
  SEAMERGE_MEASURE_CASE=$name SEAMERGE_MEASURE_OUTPUT=$values \
    SWIFT_BACKTRACE=enable=yes,interactive=no,color=no \
    swift test "${build[@]}" --skip-build --filter LargeFileMeasurements > "$log" 2>&1 &
  running=$!
  while kill -0 "$running" 2> /dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      stop "$running"
      wait "$running" 2> /dev/null
      running=""
      outcome="stopped after $timeout_minutes min"
      return
    fi
    sleep 1
  done
  wait "$running"
  status=$?
  running=""
  if [ "$status" -eq 0 ] && grep -q "	#done	" "$values" 2> /dev/null; then
    outcome=complete
  else
    outcome="ended with status $status"
  fi
}

failed=0
statuses=()
for name in "${cases[@]}"; do
  for run in $(seq 1 "$runs"); do
    values=$work/values/$name-$run.tsv
    log=$work/logs/$name-$run.log
    : > "$values"
    progress "$name run $run of $runs"
    run_case "$name" "$values" "$log"
    phase=$(awk -F'\t' '$2 == "#phase" { phase = $3 } END { print phase }' "$values")
    if [ "$outcome" != complete ]; then
      failed=1
      outcome="$outcome during ${phase:-the start}"
      grep -E 'recorded an issue|Fatal error|Crash' "$log" | head -n 5 >&2
    fi
    statuses+=("# $name run $run: $outcome")
    progress "$name run $run: $outcome"
  done
done

printf '# Large-file measurements of %s, %s, %d run(s) per case\n' "$measured" \
  "$(date '+%Y-%m-%d %H:%M')" "$runs"
printf '# %s, %s GB, macOS %s\n' "$(sysctl -n machdep.cpu.brand_string)" \
  $(($(sysctl -n hw.memsize) / 1073741824)) "$(sw_vers -productVersion)"
printf '%s\n' "${statuses[@]}"

# The values of each case and metric in the order they were first measured,
# with the median and the 95th percentile: the value at half and at 95 % of
# the sorted values, counted from the lower end.
for name in "${cases[@]}"; do
  cat "$work/values/$name"-*.tsv
done | awk -F'\t' -v start="$start" -v compare="$compare" '
  BEGIN {
    if (compare != "") {
      while ((getline line < compare) > 0) {
        if (line ~ /^#/ || line ~ /^case /) continue
        split(line, field, " ")
        before[field[1] SUBSEP field[2]] = field[3]
      }
    }
  }
  $2 ~ /^#/ { next }
  {
    key = $1 SUBSEP $2
    if (!(key in count)) {
      order[++keys] = key
      unit[key] = $4
      first[key] = $5
      clock[key] = $6
    }
    value[key, ++count[key]] = $3 + 0
  }
  END {
    header = sprintf("%-12s %-36s %10s %10s %4s %-7s %-8s %7s", "case", "metric", "median", \
      "p95", "n", "unit", "time", "elapsed")
    if (compare != "") header = header sprintf(" %10s %8s", "before", "change")
    print header
    for (k = 1; k <= keys; k++) {
      key = order[k]
      n = count[key]
      for (i = 1; i <= n; i++) sorted[i] = value[key, i]
      for (i = 2; i <= n; i++) {
        v = sorted[i]
        for (j = i - 1; j >= 1 && sorted[j] > v; j--) sorted[j + 1] = sorted[j]
        sorted[j + 1] = v
      }
      median = sorted[int(n / 2) + 1]
      p = int(n * 0.95) + 1
      p95 = sorted[p > n ? n : p]
      elapsed = int(first[key] - start)
      split(key, name, SUBSEP)
      row = sprintf("%-12s %-36s %10.1f %10.1f %4d %-7s %-8s %4d:%02d", name[1], name[2], median, \
        p95, n, unit[key], clock[key], elapsed / 60, elapsed % 60)
      if (compare != "") {
        if (key in before && before[key] + 0 != 0) {
          change = (median - before[key]) / before[key] * 100
          row = row sprintf(" %10.1f %+7.1f%%%s", before[key], change, \
            change > 15 || change < -15 ? "!" : "")
        } else {
          row = row sprintf(" %10s %8s", "-", "-")
        }
      }
      print row
    }
  }'

progress "done"
exit "$failed"
