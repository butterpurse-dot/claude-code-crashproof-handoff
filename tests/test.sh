#!/usr/bin/env bash
# Tests for hooks/session-resume.sh. Runs in a temp dir; touches nothing else.
set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/session-resume.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export SESSION_WRAP_MEM="$T/mem"
M="$SESSION_WRAP_MEM"
mkdir -p "$M" "$T/elsewhere" "$T/shop-repo"
pass=0; fail=0

check() { # name, haystack, needle, want(1=present,0=absent)
  if printf '%s' "$2" | grep -qF -- "$3"; then got=1; else got=0; fi
  if [ "$got" = "$4" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi
}
run() { CLAUDE_PROJECT_DIR="$1" bash "$HOOK" "${@:2}"; }

# 1. empty memory dir: silent, exit 0
out="$(run "$T/elsewhere")"; rc=$?
check "empty is silent" "x$out" "x" 1
[ -z "$out" ] && [ "$rc" = 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: empty output/exit ($rc)"; }

# 2. --dir prints the memory dir; default is derived from HOME
check "--dir honours override" "$(run "$T/elsewhere" --dir)" "$M" 1
mkdir -p "$T/hc/.claude" "$T/hn"
check "--dir default with ~/.claude" "$(SESSION_WRAP_MEM= HOME="$T/hc" bash "$HOOK" --dir)" "$T/hc/.claude/projects/$(printf %s "$T/hc" | tr / -)/memory" 1
check "--dir default without ~/.claude" "$(SESSION_WRAP_MEM= HOME="$T/hn" bash "$HOOK" --dir)" "$T/hn/.session-wrap/memory" 1

# 3. pointers: live lines shown for every project, superseded hidden
cat > "$M/MEMORY.md" <<'EOF'
- [a](project_alpha_handoff_20260102.md) — ★READ FIRST FOR ALPHA (current)★ alpha state
- [a-old](project_alpha_handoff_20260101.md) — READ FIRST FOR ALPHA (superseded)
- [s](project_shop_handoff_20260102.md) — ★READ FIRST FOR SHOP (current)★ shop state
- [note](some_note.md) — unrelated memory
EOF
echo ok > "$M/project_alpha_handoff_20260102.md"; echo ok > "$M/project_shop_handoff_20260102.md"
out="$(run "$T/elsewhere")"
check "header shown" "$out" "RESUME POINTERS" 1
check "alpha pointer shown" "$out" "alpha state" 1
check "shop pointer shown" "$out" "shop state" 1
check "superseded hidden" "$out" "20260101" 0
check "unrelated memory hidden" "$out" "some_note" 0
check "no warnings when clean" "$out" "WARN" 0
check "no heartbeat when clean" "$out" "UNWRAPPED" 0

# 4. unwrapped heartbeat: flagged, even in a file MEMORY.md does not point to
printf '## VERIFIED STATE\nx\n\n## LIVE STATE (heartbeat)\nnext: step 4\n' > "$M/project_beta_handoff_20260103.md"
out="$(run "$T/elsewhere")"
check "untagged heartbeat flagged" "$out" "UNWRAPPED HEARTBEAT" 1
check "heartbeat file named" "$out" "project_beta_handoff_20260103.md" 1
rm "$M/project_beta_handoff_20260103.md"

# 5. a prose mention of the heading is not a heartbeat
echo 'we removed the ## LIVE STATE (heartbeat) block' > "$M/project_alpha_handoff_20260102.md"
check "prose mention not flagged" "$(run "$T/elsewhere")" "UNWRAPPED" 0

# 6. heartbeat with no MEMORY.md at all
mkdir -p "$T/mem2"; printf '## LIVE STATE (heartbeat)\nx\n' > "$T/mem2/project_new_handoff_20260103.md"
check "heartbeat without index" "$(SESSION_WRAP_MEM="$T/mem2" run "$T/elsewhere")" "project_new_handoff_20260103.md" 1

# 7. warnings: two live pointers for one project, pointer to a missing file
echo '- [a2](project_alpha_handoff_20260104.md) — ★READ FIRST FOR ALPHA (current)★ newer' >> "$M/MEMORY.md"
out="$(run "$T/elsewhere")"
check "duplicate live pointer warned" "$out" "two live handoff pointers" 1
check "duplicate names the project" "$out" "ALPHA" 1
check "missing file warned" "$out" "missing file: project_alpha_handoff_20260104.md" 1
sed -i '$d' "$M/MEMORY.md"

# 8. force-load: rules + now + only that project's pointer
printf 'RULE never deploy on Friday\n' > "$M/shop_rules.md"; printf 'NOW waiting on review\n' > "$M/shop_now.md"
printf '# comment\n\nshop-repo | SHOP | shop_rules.md | shop_now.md\n' > "$M/session-wrap.conf"
out="$(run "$T/shop-repo")"
check "rules force-loaded" "$out" "RULE never deploy on Friday" 1
check "now force-loaded" "$out" "NOW waiting on review" 1
check "own pointer kept" "$out" "shop state" 1
check "other pointers dropped" "$out" "alpha state" 0
check "rules come first" "$(printf '%s' "$out" | head -n 1)" "RULE never deploy on Friday" 1
out="$(run "$T/elsewhere")"
check "no force-load elsewhere" "$out" "RULE never deploy on Friday" 0
check "all pointers elsewhere" "$out" "alpha state" 1

# 9. force-load matches a git worktree that lives outside the repo path
if git -C "$T/shop-repo" init -q 2>/dev/null \
   && git -C "$T/shop-repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
   && git -C "$T/shop-repo" worktree add -q "$T/wt-feature" 2>/dev/null; then
  check "worktree force-loads" "$(run "$T/wt-feature")" "RULE never deploy on Friday" 1
else
  echo "SKIP: git worktree test (git unavailable)"
fi

# 10. plugin packaging: the hooks.json command runs the hook from CLAUDE_PLUGIN_ROOT
ROOT="$(dirname "$(dirname "$HOOK")")"
cmd="$(sed -n 's/.*"command": "\(.*\)",$/\1/p' "$ROOT/hooks/hooks.json" | sed 's/\\"/"/g')"
check "plugin hook command found" "$cmd" 'CLAUDE_PLUGIN_ROOT' 1
check "plugin hook command runs" "$(CLAUDE_PROJECT_DIR="$T/elsewhere" CLAUDE_PLUGIN_ROOT="$ROOT" bash -c "$cmd")" "alpha state" 1

# 10b. Gemini CLI substitutes ${extensionPath} as text and sets no CLAUDE_PLUGIN_ROOT
gcmd="${cmd//\$\{extensionPath\}/$ROOT}"
gout="$(env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$T/elsewhere" bash -c "$gcmd")"
check "gemini-style command runs" "$gout" "alpha state" 1
check "--json wraps as hook JSON" "$gout" '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"' 1
check "--json is one line" "$(printf '%s\n' "$gout" | wc -l | tr -d ' ')" "1" 1
[ -z "$(SESSION_WRAP_MEM="$T/none" bash "$HOOK" --json)" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: --json silent when empty"; }

# 11. the memory-dir one-liner in the skill agrees with the hook
oneliner="$(grep -o 'echo "${SESSION_WRAP_MEM:-[^`]*' "$ROOT/skills/session-wrap/SKILL.md")"
check "skill carries the memory-dir one-liner" "$oneliner" "session-wrap/memory" 1
for h in "$T/hc" "$T/hn"; do
  [ "$(SESSION_WRAP_MEM= HOME="$h" bash -c "$oneliner")" = "$(SESSION_WRAP_MEM= HOME="$h" bash "$HOOK" --dir)" ] \
    && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: one-liner equals --dir ($h)"; }
done
[ "$(SESSION_WRAP_MEM=/x/y bash -c "$oneliner")" = "/x/y" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: one-liner honours override"; }

# 12. install.sh: every target puts the skill and hook where its agent reads them, in a scratch HOME
inst() { # home, target
  env -u CLAUDE_CONFIG_DIR -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME -u DSH_HOME -u SESSION_WRAP_MEM \
    HOME="$1" bash "$ROOT/install.sh" "$2"
}
for spec in "claude|.claude/skills|.claude/hooks/session-resume.sh" \
            "codex|.agents/skills|.codex/hooks/session-resume.sh" \
            "opencode|.config/opencode/skills|.config/opencode/hooks/session-resume.sh" \
            "dsh|.dsh/skills|.dsh/hooks/session-resume.sh" \
            "kilo|.kilo/skills|.config/kilo/hooks/session-resume.sh" \
            "generic|.agents/skills|.session-wrap/session-resume.sh"; do
  IFS='|' read -r tgt sk hk <<< "$spec"
  H="$T/inst-$tgt"; mkdir -p "$H"
  out="$(inst "$H" "$tgt")"; rc=$?
  [ "$rc" = 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: install $tgt exit $rc"; }
  cmp -s "$ROOT/skills/session-wrap/SKILL.md" "$H/$sk/session-wrap/SKILL.md" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: install $tgt skill at $sk"; }
  [ -x "$H/$hk" ] && cmp -s "$HOOK" "$H/$hk" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: install $tgt hook at $hk"; }
  mem="$(env -u SESSION_WRAP_MEM HOME="$H" bash "$H/$hk" --dir)"
  [ -f "$mem/MEMORY.md" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: install $tgt MEMORY.md in $mem"; }
  check "install $tgt names the hook" "$out" "$H/$hk" 1
done
# the installed generic hook works end to end from its own location
H="$T/inst-generic"; mem="$(env -u SESSION_WRAP_MEM HOME="$H" bash "$H/.session-wrap/session-resume.sh" --dir)"
mem="${mem:-$T/inst-nomem}"; mkdir -p "$mem"  # never write outside the temp dir if the hook is missing
echo '- [g](project_gen_handoff_20260105.md) — ★READ FIRST FOR GEN (current)★ gen state' > "$mem/MEMORY.md"
echo ok > "$mem/project_gen_handoff_20260105.md"
check "installed generic hook prints pointers" "$(env -u SESSION_WRAP_MEM HOME="$H" bash "$H/.session-wrap/session-resume.sh")" "gen state" 1
check "generic prints the AGENTS.md step" "$(inst "$H" generic)" "## Session handoff" 1
check "reinstall keeps the index" "$(cat "$mem/MEMORY.md")" "gen state" 1
# a changed copy is backed up, an identical one is not
[ ! -e "$H/.agents/skills/session-wrap/SKILL.md.bak" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: identical reinstall made a .bak"; }
echo "local edit" >> "$H/.agents/skills/session-wrap/SKILL.md"
inst "$H" generic >/dev/null
check "changed skill backed up" "$(cat "$H/.agents/skills/session-wrap/SKILL.md.bak" 2>/dev/null)" "local edit" 1
cmp -s "$ROOT/skills/session-wrap/SKILL.md" "$H/.agents/skills/session-wrap/SKILL.md" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: reinstall restores the skill"; }
inst "$T/inst-bad" nosuch >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: unknown target exit $rc"; }

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
