# crashproof-handoff

**A Claude Code session-wrap skill and SessionStart hook, taken from a setup that runs several long-lived projects at once.**

This is not a "summarise the chat into a file" skill. It is a closeout routine with a resume guarantee, built up over months of use across several projects, with the lessons that cost real sessions left in.

## What is different

| | What it does | Why it matters |
|---|---|---|
| **Read-first pointer chain** | Each wrap writes a dated handoff and tags its line in `MEMORY.md` as `★READ FIRST FOR <PROJECT> (current)★`; the previous one is marked superseded and stays on disk. | You get one live pointer per project and a history of every earlier handoff. Nothing is overwritten. |
| **Project-agnostic resume hook** | At session start the hook prints every live pointer, for every project, from any directory. | Adding a project means tagging one line. No per-project hook, and it still works when `MEMORY.md` grows past the 200-line auto-load limit. |
| **Rules carry forward** | Owner rules and paid-for lessons go into a short per-project rules file the moment they are given. The hook loads that file in full for that project. | A handoff gets rewritten; a rule should not have to be repeated. "Anything the owner said twice must now be in the rules file" is checked at wrap. |
| **10,000-character budget** | Hook context is cut at about 10,000 characters, so a project with a rules file gets rules, short state and only its own pointer. | The rules arrive whole instead of being cut off behind a list of other projects. |
| **Heartbeat** | Mid-session, after each sub-task and before any risky step, Claude writes a small `LIVE STATE` block into the handoff. | A crash, a killed terminal or an exhausted budget costs one step, not the session. |
| **Crash detection** | A clean wrap deletes the heartbeat block. The hook lists any handoff that still has one as `UNWRAPPED HEARTBEAT`. | The next session knows the last one never finished, and where its last known state is. |
| **Reconciliation gate** | Before a wrap counts as done, Claude lists every decision, open item and owner correction from the conversation and quotes the line where each landed, or marks it dropped with a reason. | "I think it's covered" is how things get lost. |
| **State-store routing** | The skill routes by project: one project's database, another's, or memory-only. It never writes one project's tables from another project's session. | Includes the gotchas that were learned the hard way (below). |
| **Redaction** | Keys, tokens, passwords, balances and personal data are stripped before any save. The handoff says where a value lives, never the value. | Handoffs get pasted, synced and committed. |
| **Tagging checks** | The hook warns when a project has two live pointers or a pointer to a missing file. | Both mistakes silently break the resume guarantee. |

## What the next session sees

Normal start, from any directory:

```
RESUME POINTERS (read the matching handoff BEFORE working on that project; memory dir /home/you/.claude/projects/-home-you/memory/):
- [project_shop_handoff_20260302.md](project_shop_handoff_20260302.md) — ★READ FIRST FOR SHOP (current)★ 03-02: checkout fix deployed, refunds still blocked on the payment provider
- [project_blog_handoff_20260214.md](project_blog_handoff_20260214.md) — ★READ FIRST FOR BLOG (current)★ 02-14: migration done, images not yet moved
```

After a session that died (run `bash demo.sh` to see the whole sequence in a temp dir):

```
UNWRAPPED HEARTBEAT (a session ended without /session-wrap; read the LIVE STATE block in): project_shop_handoff_20260302.md
```

## Lessons kept in the skill

These are in `SKILL.md` because each one cost a session:

- A guardrail hook that blocks dangerous commands usually greps the whole command. If your handoff text or SQL contains a literal blocked pattern (a destructive git command, say), the save itself is blocked. Paraphrase it.
- A multi-row `INSERT … VALUES` is atomic: one bad row drops all of them. Insert per row.
- A `CHECK`-constrained status column accepts its listed values only. Verify the schema before writing; notes about a schema go stale.
- For anything live, the external system of record is the truth, not the handoff. A wrap never flips a live setting.
- Do not remove the hook as a "duplicate" of `MEMORY.md` auto-loading. It adds the read-before-working instruction and survives the 200-line limit.

## Install

### As a plugin

Inside Claude Code:

```
/plugin marketplace add butterpurse-dot/claude-code-crashproof-handoff
/plugin install crashproof-handoff@crashproof-handoff
```

The plugin registers the hook for you; there is no settings edit. The skill is then named `/crashproof-handoff:session-wrap`.

### By hand

```bash
git clone https://github.com/butterpurse-dot/claude-code-crashproof-handoff.git
```

```bash
bash claude-code-crashproof-handoff/install.sh
```

The installer copies two files into `~/.claude` (backing up any it would overwrite), creates the memory dir, and prints one hook entry for you to add to `~/.claude/settings.json`:

```json
"SessionStart": [
  { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/session-resume.sh" } ] }
]
```

It does not edit your settings for you. Use one install method, not both, or the hook runs twice.

## Use

- **End of session:** `/session-wrap` (plugin install: `/crashproof-handoff:session-wrap`), or "wrap up", "save context", "prepare handoff".
- **During the session:** the skill tells Claude when to write a heartbeat. Say "checkpoint" to force one.
- **Next session:** nothing. The hook prints the pointers.

To make heartbeats start from the first message, add one line to your `CLAUDE.md`:

```
After each completed sub-task and before any risky step, write a heartbeat as described in the session-wrap skill.
```

## Make it yours

The skill is meant to be edited. Three places:

1. **§2 routes.** (Hand install only: a plugin update overwrites its copy of the skill, so install by hand if you plan to edit it.) Replace the three placeholder routes with one per project you own: where its state lives, how to connect, and its gotchas. `examples/state-store.sql` has working tables for the Postgres route.
2. **Rules files.** Copy `examples/session-wrap.conf` into the memory dir and list the projects whose rules must always load.
3. **Resume prompt.** Put your own standing instructions in the last line of the template.

## How it is laid out

- Memory dir: `~/.claude/projects/<your-home-as-a-slug>/memory/`. Print it with `echo "${SESSION_WRAP_MEM:-$HOME/.claude/projects/$(printf %s "$HOME" | tr / -)/memory}"`; override with `SESSION_WRAP_MEM`.
- `MEMORY.md` there is the index. `project_<proj>_handoff_<YYYYMMDD>.md` are the handoffs. `<proj>_rules.md` and `<proj>_now.md` are the always-loaded files.
- One memory dir for all projects is deliberate: the pointers reach you whichever directory you start in.
- The hook needs bash, git, grep and sed. No jq, no Python, no network.

## Limits

- **Heartbeats and the gate depend on the model following the skill.** The hook is plain code with tests; the skill is instructions.
- **Redaction is an instruction, not a scanner.** Check a handoff before you paste it anywhere public.
- **Tested:** the hook (`bash tests/test.sh`, 30 checks), the installer, the example tables with the skill's `INSERT`s on PostgreSQL 16, and the plugin loaded from a local folder on Claude Code 2.1 (manifest validates, hook fires, skill is listed).
- **Mileage:** the pointer chain, hook, rules files and state-store routing have months of use. The heartbeat, crash detection, reconciliation gate, redaction rule, tagging checks and plugin packaging are new.

## Files

```
skills/session-wrap/SKILL.md     the skill
hooks/session-resume.sh          the SessionStart hook
hooks/hooks.json                 registers the hook when installed as a plugin
.claude-plugin/                  plugin and marketplace manifests
examples/session-wrap.conf       force-load config for rules files
examples/state-store.sql         example Postgres state store
install.sh                       copies skill and hook into ~/.claude
tests/test.sh                    hook tests
demo.sh                          prints what the hook shows after a clean wrap and after a killed session
```

## License

MIT
