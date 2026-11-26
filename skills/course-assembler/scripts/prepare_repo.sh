#!/usr/bin/env bash
# Prepare an empty destination as its own local Git repository.
set -euo pipefail

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 ]] || fail "Usage: $0 DESTINATION"
dest=$1
[[ -n "$dest" ]] || fail 'Destination required'
case "$dest" in
  '~') dest=$HOME ;;
  '~/'*) dest="$HOME/${dest:2}" ;;
esac

if [[ -L "$dest" || ( -e "$dest" && ! -d "$dest" ) ]]; then
  fail "Destination must be a directory, not a file or symlink: $dest"
fi
mkdir -p -- "$dest"
dest=$(cd -- "$dest" && pwd -P)
contents=$(find "$dest" -mindepth 1 -maxdepth 1 ! -name .git -print -quit)
[[ -z "$contents" ]] || fail "Destination is not empty: $dest"

if [[ -e "$dest/.git" || -L "$dest/.git" ]]; then
  [[ -d "$dest/.git" && ! -L "$dest/.git" ]] || fail 'Expected a local .git directory'
  top=$(git -C "$dest" rev-parse --show-toplevel)
  [[ "$top" == "$dest" ]] || fail 'Destination is not its own Git repository'
  history=$(git -C "$dest" rev-list --all --max-count=1)
  [[ -z "$history" ]] || fail 'Destination repository already has commits'
  tracked=$(git -C "$dest" ls-files)
  [[ -z "$tracked" ]] || fail 'Destination repository already has tracked files'
else
  git init -- "$dest"
fi
printf 'Prepared local repository: %s\n' "$dest"
