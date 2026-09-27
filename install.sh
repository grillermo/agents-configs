#!/usr/bin/env bash
# Symlink this repo's skills/, rules/ and statusline script into ~/.claude so a
# fresh machine picks them up, register the status line in settings.json, and
# register the file_server MCP with the claude CLI.
# Idempotent: re-running is a no-op. This repo is the source of truth, so
# anything already sitting at a destination is overridden -- a real file or
# directory is moved aside to <name>.bak first, a stray symlink is just redone.
# A skill/rule this repo used to symlink but no longer has is unlinked too.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Always ~/.claude, never $CLAUDE_CONFIG_DIR: settings.json points the status
# line at the literal path ~/.claude/statusline-command.sh, so a config dir
# elsewhere (a session swap, say) still reads its skills and rules from here.
claude_dir="$HOME/.claude"
mkdir -p "$claude_dir"

linked=0
replaced=0
removed=0

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

# Removes a dest_dir entry that is our own symlink into src_dir but whose
# source no longer exists there -- a skill/rule deleted from the repo since
# the last install. Never touches a real file/directory, or a symlink this
# script didn't create (someone else's stuff at that name is left alone).
prune_stale() {
  local src_dir=$1
  local dest_dir=$2

  [ -d "$dest_dir" ] || return 0

  local existing=("$dest_dir"/*)
  # -e alone is wrong here: it follows symlinks, so a broken one (exactly
  # what this function looks for) reads as "empty dir" and short-circuits.
  [ -e "${existing[0]}" ] || [ -L "${existing[0]}" ] || return 0

  local dest target
  for dest in "${existing[@]}"; do
    [ -L "$dest" ] || continue
    target=$(readlink "$dest")
    case "$target" in
      "$src_dir"/*)
        [ -e "$target" ] && continue
        rm "$dest"
        echo "  removed $(basename "$dest") (no longer in repo)"
        removed=$((removed + 1))
        ;;
    esac
  done
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

  prune_stale "$src_dir" "$dest_dir"
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

# User scope, so every project on this machine gets it. The command points at
# this checkout: moving the repo means `claude mcp remove file_server -s user`
# and re-running this script. CLAUDE_BIN exists for the tests.
register_mcp() {
  local claude_bin=${CLAUDE_BIN:-claude}

  if ! command -v "$claude_bin" >/dev/null 2>&1; then
    echo "mcp: skipped (claude not installed)"
    return 0
  fi

  if "$claude_bin" mcp get file_server >/dev/null 2>&1; then
    echo "mcp: file_server already registered"
    return 0
  fi

  "$claude_bin" mcp add --scope user file_server -- ruby "$repo_root/mcp/file_server/server.rb" >/dev/null
  echo "mcp: file_server registered"
}

echo "installing into $claude_dir"
echo

link_dir skills
link_dir rules
link_statusline
register_statusline
register_mcp

echo
echo "$linked linked, $replaced replaced. $removed removed."
