---
name: session-wrap
description: Project-aware end-of-session closeout — refresh the read-first handoff memory + repoint MEMORY.md (works for ANY project), then sync the CURRENT project's state store if it has one. Use at session end, high context (~70%+), or "save context", "prepare handoff", "wrap up", "save the session". Auto-checkpoints mid-session.
---

# Session Wrap (project-aware closeout)

Two parts: §1 is universal; §2 routes by project (state tables are per-project — never write one project's tables for another). §0 = mid-session heartbeat (below). `<MEM>` = the memory dir printed by `echo "${SESSION_WRAP_MEM:-$([ -d ~/.claude ] && echo ~/.claude/projects/$(printf %s "$HOME" | tr / -)/memory || echo ~/.session-wrap/memory)}"`.

**Redact before ANY save** (heartbeat, handoff memory, rules/now files, DB rows, resume prompt): strip API keys, tokens, passwords, private keys, account numbers and balances, personal data, anything identifying live accounts. Write `<REDACTED — see vault>` or paraphrase ("live balance verified, not recorded here"). Naming WHERE the real value lives is fine; the value is not. Same pattern as the guardrail paraphrase rule in §2 — keep both.

## 0. Heartbeat checkpoint — MID-SESSION (handoff memory ONLY)
After each completed sub-task, and BEFORE any long/risky step (big refactor, deploy, DB migration), refresh ONLY the project's current §1 handoff file (create it if none): a `## LIVE STATE (heartbeat)` block — what just finished, what is in flight, the next step. Replace the previous block, never append; target <15 lines written. Keep the heading exact: the hook matches it.
- Do NOT re-tag `MEMORY.md`, touch any database, or emit the resume prompt — those stay end-of-session (§1 tag, §2, §3). At wrap, fold the block into verified state and delete it.
- A crash at any point now costs at most one step of memory. `session-resume.sh` lists every handoff still holding the block as `UNWRAPPED HEARTBEAT` at next start, so an untagged first-heartbeat file is still found.

## 1. Handoff memory — ALWAYS (any project)
Write/update `<MEM>/project_<proj>_handoff_<YYYYMMDD>.md`: verified state (key SHAs, what landed, OPEN decisions, ordered next-work, mandates). In `<MEM>/MEMORY.md`, tag its index line `★READ FIRST FOR <PROJECT> (current)★`; mark the prior one "(superseded)". Old handoffs stay on disk: the superseded chain is the project's history.
- The SessionStart hook `session-resume.sh` is PROJECT-AGNOSTIC: it injects EVERY line matching `READ FIRST FOR <ANY-PROJECT>` that is not marked superseded → tagging the line IS the resume guarantee for ANY project (no per-project hook needed). Keep the hook even though MEMORY.md is auto-loaded: it adds the "read the handoff BEFORE working" instruction, works from any directory, and survives MEMORY.md growing past the 200-line load limit. It also warns when a project has two live pointers or a pointer to a missing file — fix those at wrap.

**Rules carry forward.** Any new owner rule, standing guidance, working command or paid-for lesson goes into that project's always-loaded rules file the moment it is given, not only into a handoff. Rules file: `<MEM>/<proj>_rules.md`, force-loaded in full by session-resume.sh for every project listed in `<MEM>/session-wrap.conf`. Keep it short; replace rather than append. Check at wrap: anything the owner had to repeat this session must now be in it. Also rewrite `<MEM>/<proj>_now.md` (current state and next steps, kept short: hook context is cut at about 10,000 characters).

## 2. Project state-store sync — ROUTE first
Detect the project from cwd / the work this session. Then follow that project's route. Add one `###` route per project you own; the three below are the patterns.

### <project with a Postgres store> → its own database
Connect with credentials from the environment (`psql "$PROJECT_DB_URL"`), never a literal in the command. Example tables in `examples/state-store.sql`:
```sql
INSERT INTO session_handoff (session_id, handoff_prompt, created_at) VALUES ('<sid>','<resume>',now());
INSERT INTO decisions (title,rationale,applies_to,status,session,"timestamp",decided_at)
  VALUES ('<d>','<why>','<project>','implemented','<sid>',now()::text,now());   -- one INSERT per row
INSERT INTO code_map (module,path,lines,purpose,bounded_context) VALUES (...);  -- DELETE the path first if no unique constraint
```
GOTCHAS (write your own store's here; these are the kind that cost a session each): quote keyword-named columns (`decisions."timestamp"`; required for reserved words like `"order"`, harmless otherwise) and mind their type (this one is text + NOT NULL, hence `now()::text`); a CHECK-constrained column takes its listed values ONLY (`pending|implemented|superseded|deferred|rejected`); do not assume a table exists — `\d` it first; multi-row VALUES is atomic so one bad row drops all → do per-row with `-v ON_ERROR_STOP=off`. **Guardrail false-positive**: a PreToolUse hook that blocks dangerous commands greps the WHOLE Bash command — if your SQL text contains a literal blocked pattern (`reset --hard`, `git push`, `git clean`), the whole command is BLOCKED. Paraphrase such strings in handoff/decision text (e.g. "destructive git" not the literal).

### <project that runs live> → its own store (NOT another project's)
VERIFY the schema before writing; notes about it go stale. Live infra — the external system of record (payment provider, production DB, the running service) is truth, not the handoff; never flip a live flag or setting as part of a wrap.

### <everything else> → memory-only
No DB state store — the §1 handoff memory IS the record. Note this; don't write any other project's tables.

## 3. Emit the RESUME PROMPT (the last artifact — what the user pastes into next Claude)
After saving, OUTPUT a fenced copy-paste prompt for the next session. The SessionStart hook already injects the handoff pointer, so this prompt adds only: reload-checks + the OPEN decision(s) the user must make. Template:
```
Resume <project>. Read memory <handoff-file> first, then skill /<project-map-skill>.
Verified state: <1-line: key SHA + what's live + the gated/blocked thing>.
First: 1) /context — <any reload-check, e.g. measure newly-loaded plugin cost>; 2) <confirm-loaded check>.
Then my decision on <OPEN FORK>: [PICK ONE] (a) <rec> (b) … (c) …
<your standing per-session instructions, e.g. verify before claiming done>
```
Keep it SHORT — pointers + decisions, not a state dump (state lives in the handoff memory + DB; don't duplicate → context pollution). Also paste this prompt into the handoff memory under a `## RESUME PROMPT` heading so it's queryable, not lost in chat.

## Completion (verify, quote results)
- **Reconciliation gate — run FIRST, mandatory.** Scan the whole conversation (not just memory) and list every decision, open item, owner correction and mandate from this session. For EACH, quote it + where it landed (handoff-memory line, rules-file line, or DB row) or mark `DROPPED: <one-line reason>`. "I think it's covered" is not allowed — point to the line or mark it dropped. Anything unaccounted → write it now (refresh §3 if an OPEN decision changed), then re-list.
- §1: the handoff memory's MEMORY.md line carries `(current)`; prior marked superseded; `grep -c 'LIVE STATE (heartbeat)' <handoff>` = 0.
- §2: for a DB project, `SELECT max(created_at) FROM session_handoff;` ≈ now + the row counts you wrote. For memory-only, say so.
- §3: the resume prompt is emitted AND saved into the handoff memory.
