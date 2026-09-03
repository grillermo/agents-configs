#!/usr/bin/env bash
# Symlink this repo's skills/ and rules/ into ~/.claude so a fresh machine picks
# them up. Idempotent: re-running is a no-op. Never clobbers a real file or a
# symlink pointing somewhere outside this repo.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

linked=0
skipped=0

link_dir() {
  local kind=$1
  local src_dir="$repo_root/$kind"
  local dest_dir="$claude_dir/$kind"

  [ -d "$src_dir" ] || return 0

  # Nothing to link (an empty dir makes the glob expand to itself).
  local entries=("$src_dir"/*)
  [ -e "${entries[0]}" ] || return 0

  echo "linking $kind/"
  mkdir -p "$dest_dir"

  local src name dest current
  for src in "${entries[@]}"; do
    name=$(basename "$src")
    dest="$dest_dir/$name"

    if [ -L "$dest" ]; then
      current=$(readlink "$dest")
      if [ "$current" = "$src" ]; then
        echo "  ok   $name"
        linked=$((linked + 1))
      else
        echo "  skip $name (symlink points to $current)"
        skipped=$((skipped + 1))
      fi
      continue
    fi

    if [ -e "$dest" ]; then
      echo "  skip $name (real file already at $dest)"
      skipped=$((skipped + 1))
      continue
    fi

    ln -s "$src" "$dest"
    echo "  ok   $name"
    linked=$((linked + 1))
  done
}

link_dir skills
link_dir rules

echo
echo "$linked linked, $skipped skipped."

if [ "$skipped" -gt 0 ]; then
  echo "Resolve skipped entries by hand: move the existing file into $repo_root, then re-run."
fi
