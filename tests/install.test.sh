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

# A stand-in claude CLI: logs each call into the fake HOME and remembers a
# registration, so `mcp get` answers like the real one after `mcp add`.
fakebin="$work/bin"
mkdir -p "$fakebin"
cat >"$fakebin/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$HOME/claude-calls.log"
case "$1 $2" in
  "mcp get") [ -e "$HOME/mcp-registered" ] ;;
  "mcp add") : >"$HOME/mcp-registered" ;;
esac
EOF
chmod +x "$fakebin/claude"

# The install dir is hardcoded to $HOME/.claude, so a fake HOME is what isolates
# a test run. CLAUDE_CONFIG_DIR is set here too, to prove it is ignored.
run() {
  HOME="$1" CLAUDE_CONFIG_DIR="$work/ignored" PATH="$fakebin:$PATH" "$SCRIPT"
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

# A skill this repo used to symlink but has since deleted is unlinked too.
pruned="$work/pruned"
mkdir -p "$(cfg "$pruned")/skills"
ln -s "$ROOT_DIR/skills/does-not-exist-anymore" "$(cfg "$pruned")/skills/does-not-exist-anymore"
output=$(run "$pruned")
assert_contains "removed does-not-exist-anymore (no longer in repo)" "$output"
[ -e "$(cfg "$pruned")/skills/does-not-exist-anymore" ] && fail "expected the stale symlink to be gone"

# A symlink at that name pointing outside this repo is left alone -- it isn't ours.
foreign_link="$work/foreign_link"
mkdir -p "$(cfg "$foreign_link")/skills"
ln -s "$work/elsewhere.sh" "$(cfg "$foreign_link")/skills/not-ours"
run "$foreign_link" >/dev/null
assert_link_to "$(cfg "$foreign_link")/skills/not-ours" "$work/elsewhere.sh"

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

# The file-to-s3 MCP is registered at user scope, exactly once.
mcphome="$work/mcphome"
mkdir -p "$mcphome"
output=$(run "$mcphome")
assert_contains "mcp: file-to-s3 registered" "$output"
assert_contains "mcp add --scope user file-to-s3 -- ruby $ROOT_DIR/mcp/file-to-s3/server.rb" "$(cat "$mcphome/claude-calls.log")"
output=$(run "$mcphome")
assert_contains "mcp: file-to-s3 already registered" "$output"
[ "$(grep -c 'mcp add' "$mcphome/claude-calls.log")" = 1 ] || fail "expected exactly one mcp add"

# Without the claude CLI the step is skipped, not fatal.
noclaude="$work/noclaude"
mkdir -p "$noclaude"
output=$(HOME="$noclaude" CLAUDE_BIN="$work/missing-claude" "$SCRIPT")
assert_contains "mcp: skipped (claude not installed)" "$output"

printf 'ok\n'
