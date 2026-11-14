#!/bin/bash
#
# Creates a throwaway Git repository whose merge stops with conflicts in
# OrderService.java, and prints the commands that open it in Seamerge.
#
# Usage: Examples/make-git-conflict.sh [<directory> [<helper>]]
#
#   <directory>  where the repository goes; it must not exist or must be empty.
#                Default: a new directory under $TMPDIR.
#   <helper>     path of the seamerge command inside Seamerge.app. Default:
#                $SEAMERGE_HELPER, then the Release build made by
#                Scripts/install.sh, then /Applications/Seamerge.app.
#
# History: a base commit with Base/OrderService.java on main, then the branch
# feature/discounts with A, then main with B. The merge of feature/discounts
# into main stops with conflicts: LOCAL is main (B), REMOTE is feature/discounts (A).
#
# The commands pass the Git settings with -c, so neither the global nor the
# system Git configuration is read or written. The commits get a neutral
# author and fixed dates, so every run creates the same hashes.

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [ $# -gt 2 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "usage: Examples/make-git-conflict.sh [<directory> [<helper>]]" >&2
  exit 2
fi

directory=${1:-}
if [ -z "$directory" ]; then
  directory=$(mktemp -d "${TMPDIR:-/tmp}/seamerge-example.XXXXXX")
elif [ -e "$directory" ] && [ -n "$(ls -A -- "$directory")" ]; then
  echo "make-git-conflict: $directory is not empty" >&2
  exit 1
fi
mkdir -p -- "$directory"
directory=$(cd -- "$directory" && pwd)

helper=${2:-${SEAMERGE_HELPER:-}}
if [ -z "$helper" ]; then
  for candidate in \
    "$here/../.build/install/DerivedData/Build/Products/Release/Seamerge.app/Contents/Helpers/seamerge" \
    "/Applications/Seamerge.app/Contents/Helpers/seamerge"; do
    if [ -x "$candidate" ]; then
      helper=$candidate
      break
    fi
  done
fi
if [ -z "$helper" ]; then
  helper="/path/to/Seamerge.app/Contents/Helpers/seamerge"
  echo "make-git-conflict: no helper found; pass its path or set SEAMERGE_HELPER" >&2
elif [ ! -x "$helper" ]; then
  echo "make-git-conflict: warning: $helper is not executable" >&2
fi

# Variables such as GIT_DIR, set when this runs inside a Git hook, would point
# every command at another repository.
while IFS= read -r name; do
  unset "$name"
done < <(compgen -e | grep '^GIT_' || true)
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

git_demo() {
  git -C "$directory" -c user.name=Example -c user.email=example@example.invalid \
    -c init.defaultBranch=main -c core.autocrlf=false -c merge.conflictStyle=diff3 "$@"
}

commit_count=0

# Puts one version of OrderService.java into the working tree and commits it.
commit_version() {
  local version=$1 message=$2 date
  commit_count=$((commit_count + 1))
  date=$(printf '2026-01-01T12:%02d:00+0000' "$commit_count")
  cp -- "$here/$version/OrderService.java" "$directory/OrderService.java"
  git_demo add -- OrderService.java .gitattributes
  GIT_AUTHOR_DATE=$date GIT_COMMITTER_DATE=$date git_demo commit --quiet --message "$message"
}

git_demo init --quiet
# The file keeps its bytes: CRLF lines and the missing final line break of A
# must reach the merge unchanged.
printf 'OrderService.java -text\n' > "$directory/.gitattributes"
commit_version Base "Add the order service"
git_demo switch --quiet --create feature/discounts
commit_version A "Add category discounts"
git_demo switch --quiet main
commit_version B "Harden order placement and fix shipping texts"

if GIT_AUTHOR_DATE=2026-01-01T13:00:00+0000 GIT_COMMITTER_DATE=2026-01-01T13:00:00+0000 \
  git_demo merge --no-edit feature/discounts > /dev/null 2>&1; then
  echo "make-git-conflict: the merge did not stop with a conflict" >&2
  exit 1
fi
conflicted=$(git_demo diff --name-only --diff-filter=U)
if [ "$conflicted" != "OrderService.java" ]; then
  echo "make-git-conflict: unexpected conflicted files: ${conflicted:-none}" >&2
  exit 1
fi

# Quotes a word for a POSIX shell, unless it holds only characters that need
# no quoting.
quote() {
  if [[ $1 =~ ^[A-Za-z0-9_./=:@%+,-]+$ ]]; then
    printf '%s' "$1"
  else
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  fi
}

merge_command="$(quote "$helper") merge --from-git --base \"\$BASE\" --local \"\$LOCAL\" --remote \"\$REMOTE\" --output \"\$MERGED\""
diff_command="$(quote "$helper") diff --path \"\$MERGED\" -- \"\$LOCAL\" \"\$REMOTE\""
markers=$(grep -c '^<<<<<<<' "$directory/OrderService.java" || true)

cat <<EOF
Repository: $directory
The merge of feature/discounts into main stopped with $markers conflicts in
OrderService.java.

Resolve the conflicts in Seamerge:

git -C $(quote "$directory") \\
  -c merge.tool=seamerge \\
  -c mergetool.seamerge.cmd=$(quote "$merge_command") \\
  -c mergetool.seamerge.trustExitCode=true \\
  -c mergetool.prompt=false \\
  -c mergetool.keepBackup=false \\
  mergetool

Compare the base with feature/discounts in Seamerge:

git -C $(quote "$directory") \\
  -c diff.tool=seamerge \\
  -c difftool.seamerge.cmd=$(quote "$diff_command") \\
  -c difftool.prompt=false \\
  difftool main~1 feature/discounts
EOF
