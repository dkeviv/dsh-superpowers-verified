# Superpowers on the DeepSeek Harness (DSH)

Harness reference for `using-superpowers`. Superpowers' skills are written
mostly harness-neutral; this file maps their tool expectations onto what DSH
actually provides, and records the places where DSH differs enough to change
how a skill should be executed.

Prefer this file over guessing from another harness's reference. Where DSH has
no equivalent of a tool a skill assumes, this file says so explicitly.

## Skills

Load a skill with the `skill` tool:

```json
{"name": "brainstorming"}
```

- Use the exact name from the session's skill catalog.
- The catalog is **re-sent on every turn** and may change mid-session (for
  example, after installing a new skill). Trust the latest catalog over your
  memory of an earlier one; never invoke a name you have not seen listed.
- Loading returns the skill body plus a `Base directory for this skill` banner.
  Resolve every relative path in the skill's instructions (scripts,
  `references/*.md`, templates) against that base directory. Do not assume the
  process working directory.
- Skills are discovered from the project (`<project>/.dsh/skills`,
  `<project>/.agents/skills`), then user-global (`$DSH_HOME/skills`,
  `$DSH_AGENTS_HOME/skills`, default `~/.agents/skills`), and the winner is
  chosen by precedence rank. A skill shadowed by a higher-precedence root is
  still installed but will not load — if a skill's contents look stale, check
  for a duplicate in a higher-precedence root.

## Bootstrap

DSH has no `SessionStart` hook for skills, so Superpowers' bootstrap lives in
DSH's user-global instruction file:

```
$DSH_HOME/AGENTS.md      # default ~/.dsh/AGENTS.md
```

DSH also loads `<project>/AGENTS.md` and `CLAUDE.md` from the working tree and
its ancestors, and re-reads them when they change. The user-global file is what
makes `using-superpowers` active from the first turn in every project; without
it, skills still work but fire only when you decide to look for them. See
`docs/install.md` for how this adapter installs and removes that block.

## Task lists

Use `todo_write`. It **replaces the entire list** on every call, so always send
the complete set of todos, not just the changed items. Keep exactly one item
`in_progress` while work remains. This satisfies the "create a todo per
checklist item" step in skills such as `brainstorming` and
`subagent-driven-development`.

## Subagents

DSH dispatches subagents natively:

| Tool | Use |
| --- | --- |
| `subagent` | One self-contained task in its own context. The workhorse for `subagent-driven-development` and `dispatching-parallel-agents`. |
| `subagent_fork` | A subagent that inherits this conversation's completed turns. Use when the subtask needs conversation context the prompt would otherwise have to restate. |
| `workflow` | A JavaScript script that fans work out across many subagents in phases, with `pipeline`/`parallel` barriers and schema-validated results. Use for large orchestration, not for one or two delegations. |
| `send_message` | Continue an existing child agent's conversation. |
| `interrupt_agent` | Ask a child to stop without waiting for it to stop. |

Two behaviors that bite:

- **Start independent delegations in the same assistant message.** Sequential
  tool blocks serialize them and discard the parallelism the skill is asking
  for.
- **`subagent` and `subagent_fork` default to background.** You get an id back
  immediately and are notified on completion. Either set `run_in_background:
  false` when your very next action depends on the result, or keep doing
  independent work and collect the result later with `job_output`. Never
  busy-poll a running subagent.

## Background jobs

`bash` with `run_in_background: true` returns a job id. Track every id you
start; use `job_list` / `job_output` to collect results and `job_kill` for jobs
that stopped mattering. Before claiming completion, collect every still-relevant
job — an uncollected job is unfinished work, not a passing test.

## Plan mode

DSH has real plan mode. Use `exit_plan_mode` to present a plan for approval and
leave plan mode. `brainstorming` requires that you brainstorm **before** entering
plan mode, not inside it.

`ask_user_question` asks a structured, optionally multiple-choice question and
blocks for an answer. Use it when a decision genuinely needs the human; do not
use it to ask what you could determine yourself.

## Isolation and worktrees

DSH has **no dedicated worktree tool and no managed git integration**. The
`using-git-worktrees` skill therefore takes its fallback path: create worktrees
yourself with plain `git` through `bash`.

Check DSH's file policy before assuming a worktree is usable. Under the
`workspace-write` policy, writes are confined to the session workspace, so a
worktree created outside it will be blocked; prefer a path inside the workspace
(for example `<workspace>/.worktrees/<branch>`) and add it to `.gitignore`.
Some sessions run with broader access and approval prompts disabled — don't
infer the policy from the fact that an earlier command happened to succeed.

Superpowers' own short-lived artifacts (`.superpowers/`, plan ledgers, task
briefs) live in the working tree. Add `.superpowers/` to the project's
`.gitignore`.

## File sandbox and approvals

- The active policy is reported in the runtime context (`workspace-write` or
  unrestricted). A blocked write is reported as
  `[sandbox: file access denied under <mode> mode]`.
- That message is a policy denial, not a transient error. **Do not retry the
  same operation another way to get around it.**
- When escalation *is* available, `sandbox_permissions` on a single call
  requests it and requires a `justification` written in the user's language.
  When approval prompts are disabled, escalation is rejected automatically —
  in that case, report the blocked path instead of attempting workarounds.

## Session transcripts (`diagnosing-superpowers`)

DSH stores one directory per session:

```
$DSH_HOME/sessions/<cwd-with-slashes-and-spaces-escaped>/<session-id>/
    session.v4.jsonl.zstd
    session.lock
```

The directory name encodes the session's original working directory — `/`
becomes `-` and characters such as the space in `Default Project` become octal
escapes such as `~0020`. That escaped name is how you match a transcript to the
project you are investigating.

**Transcripts are zstd-compressed JSONL, not plain JSONL.** Decompress before
reading:

```bash
zstd -dc "$DSH_HOME/sessions/<escaped-cwd>/<session-id>/session.v4.jsonl.zstd"
```

Measure before reading — a long session decompresses to far more than its size
on disk (a 85 KB transcript can be ~100 records, but hours-long sessions are
much larger), so follow the measurement and context-safety rules in
`references/context-safety.md` rather than dumping the whole stream.

Each line is one JSON record. The first record describes the session:

```json
{"type":"session","version":4,"id":"session-...","createdAt":1792037086342,
 "cwd":"/path/to/project","isSeeded":false,"delegationDepth":0}
```

Later records carry a `seq` and a `type` — for example `permission/preset`,
`sandbox/mode`, and message/tool records. Establish what the remaining record
types mean by inspecting them directly, and do not assume another harness's
record shape.

If `zstd` is unavailable, say so plainly rather than reporting an inferred
finding: the transcript is unreadable without a decompressor.

## Compaction

DSH compacts long sessions. The skill catalog is re-sent after compaction, but
an injected bootstrap block is not re-injected. If skills stop triggering deep
into a long session, that is the likely cause — re-read the skill's current
contents instead of trusting your recollection of it.
