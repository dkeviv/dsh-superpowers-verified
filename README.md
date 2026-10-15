# Superpowers for the DeepSeek Harness

[Superpowers](https://github.com/obra/superpowers) is a software-development
methodology for coding agents — brainstorming before building, writing plans,
TDD, systematic debugging, subagent-driven execution. It ships as a skill
library plus a session-start bootstrap that makes the agent actually use it.

This repo is the **DSH adapter**. It installs Superpowers into the DeepSeek
Harness, wires up the bootstrap DSH doesn't provide a hook for, and supplies the
harness reference that maps Superpowers' tool expectations onto DSH's.

DSH is not one of the harnesses upstream supports directly, so this is a
community adapter maintained here rather than a patch to upstream.

## Install

```bash
git clone https://github.com/dkeviv/superpowers-dsh.git
cd superpowers-dsh
./bin/install.sh --dry-run     # see exactly what will change
./bin/install.sh
```

That does two things:

1. **Skills** — copies all 15 Superpowers skills into DSH's global skill root
   (`$DSH_AGENTS_HOME/skills`, default `~/.agents/skills`) and registers DSH in
   `using-superpowers`'s platform-adaptation list with a pointer to
   [`references/dsh-tools.md`](references/dsh-tools.md).
2. **Bootstrap** — writes Superpowers' session-start context into DSH's
   user-global instruction file (`$DSH_HOME/AGENTS.md`, default
   `~/.dsh/AGENTS.md`), wrapped in self-managed markers.

Skills are live in a new session immediately. An already-running DSH session
picks up the bootstrap on its next turn; restart it if you want to be certain.

### Update

```bash
git pull && ./bin/install.sh
```

### Uninstall

```bash
./bin/install.sh --uninstall          # removes both parts
./bin/install.sh --uninstall --no-skills   # keep skills, drop the bootstrap
```

Uninstall only removes skills this snapshot installed and the marked bootstrap
block. Other skills in the same root and any of your own content in `AGENTS.md`
are left alone.

### Options

| Option | Effect |
| --- | --- |
| `--target <dir>` | Skill root (default `$DSH_AGENTS_HOME/skills` or `~/.agents/skills`) |
| `--dsh-home <dir>` | DSH home holding `AGENTS.md` (default `$DSH_HOME` or `~/.dsh`) |
| `--no-skills` / `--no-bootstrap` | Do just one half |
| `--dry-run` | Print intended changes, write nothing |
| `--uninstall` | Reverse the install |

## Why an adapter is needed

Superpowers' skills are mostly harness-neutral, but two things don't carry over
to DSH:

**No session-start hook.** Upstream injects `using-superpowers` via a
`SessionStart` hook (Claude Code, Codex, Cursor, Gemini, Muse, Pi, …). DSH has
no such hook — its `dsh-hooks-*` packages *provide* hooks to other harnesses
rather than consuming them. DSH's equivalent channel is its user-global
instruction file, `$DSH_HOME/AGENTS.md`, which is loaded on every turn of every
session, so the bootstrap goes there.

**Tool vocabulary.** Nothing in DSH is named `Task`, `TodoWrite`, or `Skill`.
DSH has `skill`, `todo_write`, `subagent`/`subagent_fork`/`workflow`, native
plan mode, and a file sandbox. [`references/dsh-tools.md`](references/dsh-tools.md)
is the translation layer, and the installer adds a bullet to
`using-superpowers/SKILL.md` so upstream's own platform-adaptation mechanism
points at it.

## Verification

```bash
tests/run.sh          # 57 checks, no network, no writes outside a temp dir
```

The suite covers snapshot integrity, content fidelity against the vendored
copy, idempotency, the bootstrap block's marker handling and user-content
preservation, migration from a pre-markers install, option handling, and
uninstall. It runs entirely in a throwaway prefix, so it never touches your real
skill root or `AGENTS.md`.

To verify a live install end to end, start a fresh DSH session and send
`Let's make a react todo list`. A working install invokes **brainstorming** and
asks what you actually want before any code is written.

## Layout

```
bin/install.sh                     installer / uninstaller
lib/session-start.sh               generates the bootstrap block
lib/patch-using-superpowers.mjs    registers DSH in the skill's platform list
references/dsh-tools.md            the DSH harness reference (installed into the skill)
vendor/superpowers/                unmodified upstream snapshot (MIT, see its README)
tests/run.sh                       end-to-end tests
docs/install.md                    install, update, troubleshooting notes
```

Everything DSH-specific lives outside `vendor/`, so the upstream diff stays
auditable and re-vendoring is a plain copy. See
[`vendor/superpowers/README.md`](vendor/superpowers/README.md) for the pinned
commit and update procedure.

## Known limitations

- **No worktree tool.** DSH has no managed git integration, so
  `using-git-worktrees` takes its `git worktree` fallback path. Under the
  `workspace-write` sandbox, create worktrees *inside* the workspace.
- **`diagnosing-superpowers` needs `zstd`.** DSH stores transcripts as
  `session.v4.jsonl.zstd`; the skill's session-discovery step can't read them
  without a decompressor. `references/dsh-tools.md` documents the layout and the
  decompression command.
- **Bootstrap is not re-injected after compaction.** The skill *catalog* is
  re-sent every turn, so skills keep working, but if auto-triggering seems to
  fade deep into a very long session, that's why.
- **Snapshot, not a live feed.** Skills are vendored at a pinned commit and
  update only when you `git pull` and re-run the installer.

## License

MIT, see [LICENSE](LICENSE). The vendored Superpowers skills in
`vendor/superpowers/` are Copyright (c) 2025 Jesse Vincent, also MIT — see
[NOTICE](NOTICE) and [`vendor/superpowers/LICENSE`](vendor/superpowers/LICENSE).
