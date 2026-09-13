#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/install.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

assert_contains() {
  needle=$1
  haystack=$2

  case "$haystack" in
    *"$needle"*) ;;
    *) fail "expected output to contain $needle
output:
$haystack" ;;
  esac
}

assert_link_to() {
  link=$1
  target=$2

  [ -L "$link" ] || fail "expected $link to be a symlink"
  actual=$(readlink "$link")
  [ "$actual" = "$target" ] || fail "expected $link -> $target, got $actual"
}

assert_file_is() {
  path=$1
  want=$2

  got=$(cat "$path")
  [ "$got" = "$want" ] || fail "expected $path to hold '$want', got '$got'"
}

# The install dir is hardcoded to $HOME/.claude, so a fake HOME is what isolates
# a test run. CLAUDE_CONFIG_DIR is set here too, to prove it is ignored.
run() {
  HOME="$1" CLAUDE_CONFIG_DIR="$work/ignored" "$SCRIPT"
}

# Each case gets its own fake home; this is the config dir inside it.
cfg() {
  printf '%s/.claude' "$1"
}

statusline_src="$ROOT_DIR/statusline/statusline-command.sh"

# A fresh home links everything, into ~/.claude and not CLAUDE_CONFIG_DIR.
fresh="$work/fresh"
mkdir -p "$fresh"
output=$(run "$fresh")
assert_contains "installing into $(cfg "$fresh")" "$output"
assert_contains "0 replaced." "$output"
assert_link_to "$(cfg "$fresh")/statusline-command.sh" "$statusline_src"
[ -e "$work/ignored" ] && fail "expected CLAUDE_CONFIG_DIR to be ignored"

# Re-running is a no-op: still linked, nothing replaced.
output=$(run "$fresh")
assert_contains "0 replaced." "$output"
assert_link_to "$(cfg "$fresh")/statusline-command.sh" "$statusline_src"

# A real file at a destination is overridden, with the old copy kept as .bak.
occupied="$work/occupied"
mkdir -p "$(cfg "$occupied")"
printf 'hand written\n' >"$(cfg "$occupied")/statusline-command.sh"
output=$(run "$occupied")
assert_contains "replace statusline-command.sh (old copy at statusline-command.sh.bak)" "$output"
assert_link_to "$(cfg "$occupied")/statusline-command.sh" "$statusline_src"
assert_file_is "$(cfg "$occupied")/statusline-command.sh.bak" "hand written"

# Re-running does not clobber the backup with the now-correct symlink.
run "$occupied" >/dev/null
assert_file_is "$(cfg "$occupied")/statusline-command.sh.bak" "hand written"

# A symlink pointing outside this repo is redone, with no .bak left behind.
stray="$work/stray"
mkdir -p "$(cfg "$stray")"
printf 'elsewhere\n' >"$work/elsewhere.sh"
ln -s "$work/elsewhere.sh" "$(cfg "$stray")/statusline-command.sh"
output=$(run "$stray")
assert_contains "relink  statusline-command.sh (was -> $work/elsewhere.sh)" "$output"
assert_link_to "$(cfg "$stray")/statusline-command.sh" "$statusline_src"
[ -e "$(cfg "$stray")/statusline-command.sh.bak" ] && fail "expected no .bak for a replaced symlink"

# A real directory where a skill belongs is overridden too.
skill_name=$(basename "$(find "$ROOT_DIR/skills" -mindepth 1 -maxdepth 1 | head -1)")
dirdest="$work/dirdest"
mkdir -p "$(cfg "$dirdest")/skills/$skill_name"
printf 'stale\n' >"$(cfg "$dirdest")/skills/$skill_name/leftover.txt"
run "$dirdest" >/dev/null
assert_link_to "$(cfg "$dirdest")/skills/$skill_name" "$ROOT_DIR/skills/$skill_name"
assert_file_is "$(cfg "$dirdest")/skills/$skill_name.bak/leftover.txt" "stale"

# A foreign statusLine command in settings.json is rewritten to this repo's.
foreign="$work/foreign"
mkdir -p "$(cfg "$foreign")"
printf '{"statusLine":{"type":"command","command":"echo other"},"keep":"me"}\n' >"$(cfg "$foreign")/settings.json"
output=$(run "$foreign")
assert_contains "statusLine: registered in settings.json" "$output"
got=$(jq -r '.statusLine.command' "$(cfg "$foreign")/settings.json")
[ "$got" = "bash ~/.claude/statusline-command.sh" ] || fail "statusLine not overridden, got $got"
got=$(jq -r '.keep' "$(cfg "$foreign")/settings.json")
[ "$got" = "me" ] || fail "unrelated settings key was lost"

printf 'ok\n'
