#!/usr/bin/env bash
# session-resume.sh — SessionStart hook for the session-wrap skill.
#
# Project-agnostic resume guarantee. Prints (stdout becomes session context):
#   1. EVERY MEMORY.md index line tagged "READ FIRST FOR <PROJECT>" that is not
#      marked superseded, so a new session sees the current handoff pointer for
#      any project. No project is hardcoded: tag a line and it is picked up.
#   2. UNWRAPPED HEARTBEAT: handoff files still holding a heartbeat block.
#      /session-wrap deletes that block, so one that remains belongs to a
#      session that crashed, was killed, or ran out of budget.
#   3. Warnings: a project with two live pointers, or a pointer to a missing file.
#   4. For projects listed in <MEM>/session-wrap.conf: that project's rules file
#      and now file in full, ahead of everything else.
#
#   session-resume.sh --dir    print the memory dir and exit
#
# Config: SESSION_WRAP_MEM overrides the memory dir. Needs bash, git, grep, sed.
set -u

MEM="${SESSION_WRAP_MEM:-$HOME/.claude/projects/$(printf %s "$HOME" | tr / -)/memory}"
if [ "${1:-}" = "--dir" ]; then printf '%s\n' "$MEM"; exit 0; fi
MARK='## LIVE STATE (heartbeat)'

LINES="$(grep -E 'READ FIRST FOR' "$MEM/MEMORY.md" 2>/dev/null | grep -vi 'superseded' || true)"

HB=""
for f in "$MEM"/project_*_handoff_*.md; do
  [ -f "$f" ] && grep -qxF "$MARK" "$f" && HB="$HB $(basename "$f")"
done

# Tagging mistakes that silently break the resume guarantee.
WARN=""
DUP="$(printf '%s\n' "$LINES" | sed -n 's/.*READ FIRST FOR \([A-Za-z0-9_.-]*\).*/\1/p' | sort | uniq -d | tr '\n' ' ')"
[ -n "$DUP" ] && WARN="${WARN}WARN two live handoff pointers (mark the older one superseded): ${DUP}
"
while IFS= read -r p; do
  [ -n "$p" ] && [ ! -f "$MEM/$p" ] && WARN="${WARN}WARN pointer to a missing file: ${p}
"
done <<EOF
$(printf '%s\n' "$LINES" | sed -n 's/.*](\([^)]*\)).*/\1/p')
EOF

# Matched through git too, because worktrees can live outside the repo path.
CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
COMMON="$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"

# Force-load: "match|TAG|rules-file|now-file" per line. Hook context is cut at
# about 10,000 characters, so a matched project gets its rules, its short state
# and only its own pointer; the other projects' pointers are dropped.
FORCED=""
if [ -f "$MEM/session-wrap.conf" ]; then
  while IFS='|' read -r match tag rules now; do
    match="${match// /}"; tag="${tag// /}"; rules="${rules// /}"; now="${now// /}"
    case "$match" in ''|\#*) continue ;; esac
    case "$CWD $COMMON" in
      *"$match"*)
        FORCED="$(cat "$MEM/$rules" 2>/dev/null)

$(cat "$MEM/$now" 2>/dev/null)

$(printf '%s\n' "$LINES" | grep -F "READ FIRST FOR $tag" | cut -c1-200)"
        break ;;
    esac
  done < "$MEM/session-wrap.conf"
fi

[ -z "$LINES" ] && [ -z "$HB" ] && [ -z "$FORCED" ] && exit 0

if [ -n "$FORCED" ]; then
  printf '%s\n' "$FORCED"
elif [ -n "$LINES" ]; then
  printf 'RESUME POINTERS (read the matching handoff BEFORE working on that project; memory dir %s/):\n%s\n' "$MEM" "$LINES"
fi
[ -n "$HB" ] && echo "UNWRAPPED HEARTBEAT (a session ended without /session-wrap; read the LIVE STATE block in):$HB"
[ -n "$WARN" ] && printf '%s' "$WARN"
exit 0
