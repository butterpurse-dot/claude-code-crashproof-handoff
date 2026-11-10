#!/usr/bin/env bash
# Copies the skill and the resume script into an agent's config dir.
#   bash install.sh [claude|codex|opencode|kilo|dsh|generic]     (default: claude)
# codex and generic put the skill in ~/.agents/skills, the shared location that
# Codex, opencode and other SKILL.md-aware agents read.
# It never edits a settings, hooks or AGENTS.md file: it prints what to add.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-claude}"

case "$TARGET" in
  claude)   DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}";  SKILL="$DIR/skills/session-wrap/SKILL.md" ;;
  codex)    DIR="${CODEX_HOME:-$HOME/.codex}";          SKILL="$HOME/.agents/skills/session-wrap/SKILL.md" ;;
  opencode) DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
            SKILL="$DIR/skills/session-wrap/SKILL.md" ;;
  dsh)      DIR="${DSH_HOME:-$HOME/.dsh}";             SKILL="$DIR/skills/session-wrap/SKILL.md" ;;
  kilo)     DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kilo"; SKILL="$HOME/.kilo/skills/session-wrap/SKILL.md" ;;
  generic)  DIR="$HOME/.session-wrap";                  SKILL="$HOME/.agents/skills/session-wrap/SKILL.md" ;;
  *) echo "usage: bash install.sh [claude|codex|opencode|kilo|dsh|generic]" >&2; exit 2 ;;
esac
HOOK="$DIR/hooks/session-resume.sh"
[ "$TARGET" = generic ] && HOOK="$DIR/session-resume.sh"

put() { # src dst — back up a different existing file, then copy
  mkdir -p "$(dirname "$2")"
  if [ -e "$2" ] && ! cmp -s "$1" "$2"; then cp "$2" "$2.bak"; echo "existing $2 saved as $2.bak"; fi
  cp "$1" "$2"
}
put "$SRC/skills/session-wrap/SKILL.md" "$SKILL"
put "$SRC/hooks/session-resume.sh" "$HOOK"
chmod +x "$HOOK"

MEM="$(bash "$HOOK" --dir)"
mkdir -p "$MEM"
[ -f "$MEM/MEMORY.md" ] || : > "$MEM/MEMORY.md"

cat <<EOF2
Installed for $TARGET:
  $SKILL
  $HOOK
Memory dir (handoffs, MEMORY.md index, rules files):
  $MEM

EOF2

HOOK_JSON="  \"SessionStart\": [
    { \"hooks\": [ { \"type\": \"command\", \"command\": \"bash $HOOK\" } ] }
  ]"
case "$TARGET" in
  claude) cat <<EOF2
Last step: add this to the "hooks" object in $DIR/settings.json
(merge with any SessionStart entries you already have):

$HOOK_JSON
EOF2
  ;;
  codex) cat <<EOF2
Last step: add this to the "hooks" object in $DIR/hooks.json
(create the file as { "hooks": { ... } } if you have none). Codex asks you to
trust a new hook the first time it runs.

$HOOK_JSON
EOF2
  ;;
  *) cat <<EOF2
Last step: this agent has no session-start hook, so add these lines to its
instructions file (AGENTS.md, or whatever your agent reads at start):

  ## Session handoff
  At the start of every session, run \`bash $HOOK\` and read what it prints
  before doing anything else.
  When I say "wrap up", "save context" or "prepare handoff", or the context is
  nearly full, follow $SKILL exactly.
  After each completed sub-task and before any risky step, write a heartbeat as
  that file describes.
EOF2
  ;;
esac
cat <<EOF2

Optional: copy examples/session-wrap.conf to $MEM/ to force-load a project's rules file.
EOF2
