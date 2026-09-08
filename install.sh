#!/usr/bin/env bash
# Symlink this repo's skills/, rules/ and statusline script into ~/.claude so a
# fresh machine picks them up, and register the status line in settings.json.
# Idempotent: re-running is a no-op. Never clobbers a real file or a symlink
# pointing somewhere outside this repo.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}

linked=0
skipped=0

link_one() {
  local src=$1
  local dest=$2
  local name
  name=$(basename "$dest")

  if [ -L "$dest" ]; then
    local current
    current=$(readlink "$dest")
    if [ "$current" = "$src" ]; then
      echo "  ok   $name"
      linked=$((linked + 1))
    else
      echo "  skip $name (symlink points to $current)"
      skipped=$((skipped + 1))
    fi
    return 0
  fi

  if [ -e "$dest" ]; then
    echo "  skip $name (real file already at $dest)"
    skipped=$((skipped + 1))
    return 0
  fi

  ln -s "$src" "$dest"
  echo "  ok   $name"
  linked=$((linked + 1))
}

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

  local src
  for src in "${entries[@]}"; do
    link_one "$src" "$dest_dir/$(basename "$src")"
  done
}

# The status line lives at the top level of ~/.claude, not in a subdirectory,
# because that is the path settings.json points at.
link_statusline() {
  local src="$repo_root/statusline/statusline-command.sh"
  [ -f "$src" ] || return 0

  echo "linking statusline/"
  mkdir -p "$claude_dir"
  link_one "$src" "$claude_dir/statusline-command.sh"
}

# settings.json is machine-local (it holds per-machine plugin state), so it is
# not symlinked -- just add the statusLine block if this machine lacks one.
register_statusline() {
  local settings="$claude_dir/settings.json"

  if ! command -v jq >/dev/null 2>&1; then
    echo "statusLine: skipped (jq not installed)"
    return 0
  fi

  if [ ! -f "$settings" ]; then
    echo '{}' >"$settings"
  fi

  if [ "$(jq -r '.statusLine.command // empty' "$settings")" != "" ]; then
    echo "statusLine: already set in settings.json"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  jq '.statusLine = {type: "command", command: "bash ~/.claude/statusline-command.sh", padding: 1}' \
    "$settings" >"$tmp" && mv "$tmp" "$settings"
  echo "statusLine: registered in settings.json"
}

link_dir skills
link_dir rules
link_statusline
register_statusline

echo
echo "$linked linked, $skipped skipped."

if [ "$skipped" -gt 0 ]; then
  echo "Resolve skipped entries by hand: move the existing file into $repo_root, then re-run."
fi
