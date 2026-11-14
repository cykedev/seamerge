#!/bin/bash
#
# Creates a Git repository in a prepared state, for trying `git mergetool` and
# `git difftool` by hand and for the tests of GitSupport.
#
# Usage: Scripts/make-test-repo.sh <directory> <scenario>
#
# The directory must not exist or must be empty. Scenarios:
#
#   merge        a merge that stops with a conflict
#   rebase       a rebase of three commits that stops at the second
#   cherry-pick  a cherry-pick that stops with a conflict
#   revert       a revert that stops with a conflict
#   stash        a stash pop that stops with a conflict
#   add-add      a merge of a file that both branches added
#   whitespace   a conflict between lines that differ only in whitespace
#   crlf         a conflict in a file with CRLF line endings
#   utf16        a conflict in a file stored as UTF-16 in the working tree
#   many         a merge with twelve conflicted files, one with a name beyond ASCII
#   big          a merge of a file of 50,000 lines with 40 conflicts
#   diff         three files changed in the working tree
#   diff-commits two commits to compare: git difftool HEAD~1 HEAD
#   diff-new     a file added and a file deleted in the working tree
#   diff-many    a commit of 40 files in ten folders, among them 2 added and 2
#                deleted: git difftool HEAD~1 HEAD
#
# Neither the Git configuration of the user nor that of the system is read, so
# every run creates the same commits. The repository gets a configuration of
# its own with a name and an address for further commits.

set -euo pipefail

scenarios=(merge rebase cherry-pick revert stash add-add whitespace crlf utf16 many big
  diff diff-commits diff-new diff-many)

usage() {
  echo "usage: Scripts/make-test-repo.sh <directory> <scenario>" >&2
  echo "scenarios: ${scenarios[*]}" >&2
  exit 2
}

[ $# -eq 2 ] || usage
directory=$1
scenario=$2
known=false
for name in "${scenarios[@]}"; do
  [ "$name" = "$scenario" ] && known=true
done
$known || usage

if [ -e "$directory" ] && [ -n "$(ls -A -- "$directory")" ]; then
  echo "make-test-repo: $directory is not empty" >&2
  exit 1
fi

# Variables such as GIT_DIR, set when this runs inside a Git hook, would point
# every command at another repository.
while IFS= read -r name; do
  unset "$name"
done < <(compgen -e | grep '^GIT_' || true)

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME="Ada Example" GIT_AUTHOR_EMAIL=ada@example.com
export GIT_COMMITTER_NAME="Ada Example" GIT_COMMITTER_EMAIL=ada@example.com
# Commits that Git writes itself, in a rebase or a stash, get this date as well.
export GIT_AUTHOR_DATE=2026-01-01T13:00:00+0000 GIT_COMMITTER_DATE=2026-01-01T13:00:00+0000

mkdir -p -- "$directory"
cd -- "$directory"
git init --quiet --initial-branch=main
git config user.name "Ada Example"
git config user.email ada@example.com

commit_count=0

# Commits everything in the working tree. Each commit is a minute after the
# previous one, so that the hashes are the same on every run.
commit() {
  commit_count=$((commit_count + 1))
  local date
  date=$(printf '2026-01-01T12:%02d:00+0000' "$commit_count")
  git add --all
  GIT_AUTHOR_DATE=$date GIT_COMMITTER_DATE=$date git commit --quiet --message "$1"
}

# Writes the lines "line 1" to "line <count>" into a file, or to the standard
# output when the file is "-".
write_lines() {
  if [ "$1" = - ]; then
    awk -v count="$2" 'BEGIN { for (i = 1; i <= count; i++) print "line " i }'
  else
    write_lines - "$2" > "$1"
  fi
}

# Replaces line <number> of a file with the given text. A file in UTF-16 stays
# in UTF-16.
replace_line() {
  if [ "$(head -c 2 "$1" | od -An -tx1 | tr -d ' ')" = fffe ]; then
    tail -c +3 "$1" | iconv -f UTF-16LE -t UTF-8 | replace_line_in_stream "$2" "$3" |
      to_utf16 "$1.new"
  else
    replace_line_in_stream "$2" "$3" < "$1" > "$1.new"
  fi
  mv "$1.new" "$1"
}

replace_line_in_stream() {
  awk -v number="$1" -v text="$2" 'NR == number { print text; next } { print }'
}

# Writes the standard input into a file in UTF-16 little endian with a byte
# order mark.
to_utf16() {
  { printf '\xff\xfe'; iconv -f UTF-8 -t UTF-16LE; } > "$1"
}

# Runs a Git command that is expected to stop with a conflict, and fails unless
# it did.
expect_conflict() {
  if "$@" > /dev/null 2>&1; then
    echo "make-test-repo: '$*' did not stop with a conflict" >&2
    exit 1
  fi
  if [ -z "$(git diff --name-only --diff-filter=U)" ]; then
    echo "make-test-repo: '$*' failed without a conflict" >&2
    exit 1
  fi
}

# Changes line 5 of each file differently on a branch named feature and on
# main, then merges feature into main.
merge_conflicting_lines() {
  local file
  for file in "$@"; do write_lines "$file" 10; done
  commit "Add ${*}"
  git switch --quiet --create feature
  for file in "$@"; do replace_line "$file" 5 "line 5 from feature"; done
  commit "Change line 5 on feature"
  git switch --quiet main
  for file in "$@"; do replace_line "$file" 5 "line 5 from main"; done
  commit "Change line 5 on main"
  expect_conflict git merge feature
}

case $scenario in
  merge)
    merge_conflicting_lines story.txt
    ;;

  rebase)
    write_lines notes.txt 10
    commit "Add notes"
    git switch --quiet --create feature
    replace_line notes.txt 2 "line 2 from feature"
    commit "Change line 2"
    replace_line notes.txt 5 "line 5 from feature"
    commit "Change line 5"
    replace_line notes.txt 8 "line 8 from feature"
    commit "Change line 8"
    git switch --quiet main
    replace_line notes.txt 5 "line 5 from main"
    commit "Change line 5 on main"
    git switch --quiet feature
    expect_conflict git rebase main
    ;;

  cherry-pick)
    write_lines story.txt 10
    commit "Add story"
    git switch --quiet --create feature
    replace_line story.txt 5 "line 5 from feature"
    commit "Change line 5 on feature"
    git switch --quiet main
    replace_line story.txt 5 "line 5 from main"
    commit "Change line 5 on main"
    expect_conflict git cherry-pick feature
    ;;

  revert)
    write_lines story.txt 10
    commit "Add story"
    replace_line story.txt 5 "line 5, first version"
    commit "Change line 5"
    replace_line story.txt 5 "line 5, second version"
    commit "Change line 5 again"
    expect_conflict git revert --no-edit HEAD~1
    ;;

  stash)
    write_lines story.txt 10
    commit "Add story"
    replace_line story.txt 5 "line 5 from the stash"
    git stash push --quiet
    replace_line story.txt 5 "line 5 from main"
    commit "Change line 5 on main"
    expect_conflict git stash pop
    ;;

  add-add)
    write_lines readme.txt 3
    commit "Add readme"
    git switch --quiet --create feature
    printf 'Added on feature\nwith two lines\n' > added.txt
    commit "Add a file on feature"
    git switch --quiet main
    printf 'Added on main\nwith other lines\n' > added.txt
    commit "Add a file on main"
    expect_conflict git merge feature
    ;;

  whitespace)
    printf 'func run() {\n    let a = 1\n    let b = 2\n    return a + b\n}\n' > code.txt
    commit "Add code"
    git switch --quiet --create feature
    printf 'func run() {\n\tlet a = 1\n\tlet b = 2\n    return a + b\n}\n' > code.txt
    commit "Indent with tabs"
    git switch --quiet main
    printf 'func run() {\n  let a = 1  \n  let b = 2\n    return a + b\n}\n' > code.txt
    commit "Indent with two spaces"
    expect_conflict git merge feature
    ;;

  crlf)
    printf '* -text\n' > .gitattributes
    write_lines story.txt 10
    sed -i '' $'s/$/\r/' story.txt
    commit "Add a story with CRLF line endings"
    git switch --quiet --create feature
    replace_line story.txt 5 $'line 5 from feature\r'
    commit "Change line 5 on feature"
    git switch --quiet main
    replace_line story.txt 5 $'line 5 from main\r'
    commit "Change line 5 on main"
    expect_conflict git merge feature
    ;;

  utf16)
    # Git keeps the file as UTF-8 and converts it to UTF-16 with a byte order
    # mark in the working tree, so that it merges the lines as text.
    printf '*.txt text working-tree-encoding=UTF-16LE-BOM eol=lf\n' > .gitattributes
    write_lines - 10 | to_utf16 greeting.txt
    commit "Add a greeting in UTF-16"
    git switch --quiet --create feature
    replace_line greeting.txt 5 "Grüße from feature"
    commit "Change line 5 on feature"
    git switch --quiet main
    replace_line greeting.txt 5 "Grüße from main"
    commit "Change line 5 on main"
    expect_conflict git merge feature
    ;;

  many)
    files=()
    for number in $(seq -w 1 11); do files+=("file-$number.txt"); done
    # A name beyond ASCII, which the file system and Git may normalize differently.
    files+=("Grüße.txt")
    merge_conflicting_lines "${files[@]}"
    ;;

  big)
    write_lines big.txt 50000
    commit "Add a big file"
    git switch --quiet --create feature
    awk 'NR % 1250 == 0 { print $0 " from feature"; next } { print }' big.txt > big.new
    mv big.new big.txt
    commit "Change every 1250th line on feature"
    git switch --quiet main
    awk 'NR % 1250 == 0 { print $0 " from main"; next } { print }' big.txt > big.new
    mv big.new big.txt
    commit "Change every 1250th line on main"
    expect_conflict git merge feature
    ;;

  diff)
    for file in one.txt two.txt three.txt; do write_lines "$file" 10; done
    commit "Add three files"
    replace_line one.txt 2 "line 2, changed"
    replace_line two.txt 5 "line 5, changed"
    replace_line three.txt 9 "line 9, changed"
    ;;

  diff-commits)
    write_lines story.txt 10
    write_lines notes.txt 10
    commit "Add story and notes"
    replace_line story.txt 3 "line 3, changed"
    replace_line notes.txt 7 "line 7, changed"
    commit "Change story and notes"
    ;;

  diff-many)
    for number in $(seq 1 38); do
      mkdir -p "module$((number % 10))"
      write_lines "module$((number % 10))/file$number.txt" 20
    done
    commit "Add 38 files"
    for number in $(seq 1 36); do
      replace_line "module$((number % 10))/file$number.txt" $((number % 20 + 1)) "changed"
    done
    rm module7/file37.txt module8/file38.txt
    write_lines module1/added1.txt 5
    write_lines module2/added2.txt 5
    commit "Change 36 files, add two and delete two"
    ;;

  diff-new)
    write_lines kept.txt 10
    write_lines removed.txt 10
    commit "Add two files"
    rm removed.txt
    write_lines added.txt 5
    git add --intent-to-add added.txt
    ;;
esac
