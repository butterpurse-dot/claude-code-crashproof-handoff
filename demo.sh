#!/usr/bin/env bash
# Shows what the hook prints across three session starts. Runs in a temp dir
# and touches nothing in ~/.claude. No Claude session is needed: the files are
# written here the way the skill tells Claude to write them.
set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hooks/session-resume.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export SESSION_WRAP_MEM="$T/memory" CLAUDE_PROJECT_DIR="$T"
M="$SESSION_WRAP_MEM"; mkdir -p "$M"
H="project_shop_handoff_20260302.md"
start() { printf '\n--- %s ---\n' "$1"; bash "$HOOK" | sed "s|$M|<MEM>|g"; }

# Session 1 ended with /session-wrap: handoff written, index line tagged.
printf '## VERIFIED STATE\ncheckout fix deployed at a1b2c3d, smoke test green\n' > "$M/$H"
echo "- [$H]($H) — ★READ FIRST FOR SHOP (current)★ 03-02: checkout fix deployed" > "$M/MEMORY.md"
start "session 2 starts (session 1 wrapped cleanly)"

# Session 2 writes a heartbeat before a risky step, then the terminal is killed.
printf '\n## LIVE STATE (heartbeat)\ndone: migration 0042 applied on staging, row counts match\nin flight: backfill job started 14:02, not yet checked\nnext: verify backfill, then run 0042 on prod\n' >> "$M/$H"
start "session 3 starts (session 2 was killed mid-task)"
printf '\nthe block session 3 is told to read:\n'; sed -n '/^## LIVE STATE/,$p' "$M/$H" | sed 's/^/  /'

# Session 3 finishes the work and wraps: the block is folded in and deleted.
printf '## VERIFIED STATE\nmigration 0042 on prod at d4e5f6a, backfill verified\n' > "$M/$H"
start "session 4 starts (session 3 wrapped cleanly)"
