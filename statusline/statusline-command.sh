#!/bin/bash
# Minimal Claude Code status line:
# model, effort level, current base folder name, context usage.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
folder=$(basename "$cwd")
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
# Email of the Claude account currently logged in (follows account switches).
config_dir="${CLAUDE_CONFIG_DIR:-$HOME}"
email=$(jq -r '.oauthAccount.emailAddress // empty' "$config_dir/.claude.json" 2>/dev/null)

DIM="\033[2m"
RESET="\033[0m"

parts=("$model")
[ -n "$effort" ] && parts+=("$effort")
parts+=("$folder")
if [ -n "$used" ]; then
  ctx=$(printf '%.0f' "$used")
  parts+=("ctx ${ctx}%")
fi
[ -n "$email" ] && parts+=("$email")

line=""
for p in "${parts[@]}"; do
  if [ -n "$line" ]; then
    line="${line} | ${p}"
  else
    line="$p"
  fi
done

printf "${DIM}%s${RESET}\n" "$line"
