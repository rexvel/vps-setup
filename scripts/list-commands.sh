#!/usr/bin/env bash
# Lists cleanly-enumerable Claude Code slash commands: custom commands + personal skills.
# Plugin skills (namespaced /plugin:skill) and built-ins (/help, /clear, /model, ...) -> use /help.
shopt -s nullglob

desc() {
  awk '
    /^description:[[:space:]]*>/        { folded=1; next }
    folded && /^[[:space:]]+[^[:space:]]/ { sub(/^[[:space:]]+/,""); print; exit }
    /^description:[[:space:]]*[^>[:space:]]/ { sub(/^description:[[:space:]]*/,""); print; exit }
  ' "$1" | head -1 | cut -c1-96
}

list_cmds() {
  local dir="$1" found=0 f
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue; found=1
    printf '  %-20s %s\n' "/$(basename "$f" .md)" "$(desc "$f")"
  done
  [ "$found" -eq 1 ] || echo "  (none)"
}

echo "PERSONAL COMMANDS  (~/.claude/commands)"
list_cmds ~/.claude/commands
echo; echo "PROJECT COMMANDS  (./.claude/commands)"
{ [ -d .claude/commands ] && list_cmds .claude/commands; } || echo "  (none in this project)"
echo; echo "PERSONAL SKILLS  (invoke as /name)"
found=0
for f in ~/.claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue; found=1
  printf '  %-20s %s\n' "/$(basename "$(dirname "$f")")" "$(desc "$f")"
done
[ "$found" -eq 1 ] || echo "  (none)"
echo
echo "PLUGIN SKILLS (namespaced /plugin:skill) and BUILT-INS (/clear /model /config /fork /effort ...)"
echo "  -> type  /help  for the full authoritative list"
