#!/usr/bin/env bash
# Symlink this repo's skills/, rules/ and statusline script into ~/.claude so a
# fresh machine picks them up, and register the status line in settings.json.
# Idempotent: re-running is a no-op. This repo is the source of truth, so
# anything already sitting at a destination is overridden -- a real file or
# directory is moved aside to <name>.bak first, a stray symlink is just redone.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Always ~/.claude, never $CLAUDE_CONFIG_DIR: settings.json points the status
# line at the literal path ~/.claude/statusline-command.sh, so a config dir
# elsewhere (a session swap, say) still reads its skills and rules from here.
claude_dir="$HOME/.claude"
mkdir -p "$claude_dir"

linked=0
replaced=0

link_one() {
  local src=$1
  local dest=$2
  local name
  name=$(basename "$dest")

  # -L before -e: a symlink to a missing target is still ours to replace, but
  # -e reports it as absent.
  if [ -L "$dest" ]; then
    local current
    current=$(readlink "$dest")
    if [ "$current" = "$src" ]; then
      echo "  ok      $name"
      linked=$((linked + 1))
      return 0
    fi

    rm "$dest"
    ln -s "$src" "$dest"
    echo "  relink  $name (was -> $current)"
    replaced=$((replaced + 1))
    return 0
  fi

  # A real file or directory. Keep a copy so an override is undoable; the next
  # run finds a symlink here and leaves the .bak alone.
  if [ -e "$dest" ]; then
    rm -rf "$dest.bak"
    mv "$dest" "$dest.bak"
    ln -s "$src" "$dest"
    echo "  replace $name (old copy at $name.bak)"
    replaced=$((replaced + 1))
    return 0
  fi

  ln -s "$src" "$dest"
  echo "  ok      $name"
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
  link_one "$src" "$claude_dir/statusline-command.sh"
}

# settings.json is machine-local (it holds per-machine plugin state), so it is
# not symlinked -- only the statusLine block is rewritten, to this repo's script.
register_statusline() {
  local settings="$claude_dir/settings.json"

  if ! command -v jq >/dev/null 2>&1; then
    echo "statusLine: skipped (jq not installed)"
    return 0
  fi

  if [ ! -f "$settings" ]; then
    echo '{}' >"$settings"
  fi

  local want="bash ~/.claude/statusline-command.sh"
  if [ "$(jq -r '.statusLine.command // empty' "$settings")" = "$want" ]; then
    echo "statusLine: already set in settings.json"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg cmd "$want" '.statusLine = {type: "command", command: $cmd, padding: 1}' \
    "$settings" >"$tmp" && mv "$tmp" "$settings"
  echo "statusLine: registered in settings.json"
}

echo "installing into $claude_dir"
echo

link_dir skills
link_dir rules
link_statusline
register_statusline

echo
echo "$linked linked, $replaced replaced."
