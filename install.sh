#!/usr/bin/env bash
# Copies the skill and the hook into ~/.claude. Does not edit settings.json:
# it prints the hook entry for you to add.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mkdir -p "$CLAUDE_DIR/skills/session-wrap" "$CLAUDE_DIR/hooks"
for pair in "skills/session-wrap/SKILL.md" "hooks/session-resume.sh"; do
  dst="$CLAUDE_DIR/$pair"
  if [ -e "$dst" ] && ! cmp -s "$SRC/$pair" "$dst"; then
    cp "$dst" "$dst.bak"
    echo "existing $dst saved as $dst.bak"
  fi
  cp "$SRC/$pair" "$dst"
done
chmod +x "$CLAUDE_DIR/hooks/session-resume.sh"

MEM="$(bash "$CLAUDE_DIR/hooks/session-resume.sh" --dir)"
mkdir -p "$MEM"
[ -f "$MEM/MEMORY.md" ] || : > "$MEM/MEMORY.md"

cat <<EOF
Installed:
  $CLAUDE_DIR/skills/session-wrap/SKILL.md
  $CLAUDE_DIR/hooks/session-resume.sh
Memory dir (handoffs, MEMORY.md index, rules files):
  $MEM

Last step: add this to the "hooks" object in $CLAUDE_DIR/settings.json
(merge with any SessionStart entries you already have):

  "SessionStart": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/session-resume.sh" } ] }
  ]

Optional: copy examples/session-wrap.conf to $MEM/ to force-load a project's rules file.
Then start a new session and run /session-wrap when you finish.
EOF
