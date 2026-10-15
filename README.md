# dsh-superpowers-verified

**A fork of [Superpowers](https://github.com/obra/superpowers) for the
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH)** —
the full Superpowers methodology (brainstorming, planning, TDD, systematic
debugging, subagent-driven execution) adapted to run on DSH, installed
**verifiably and reversibly**.

Superpowers is an agentic software-development methodology by
[Jesse Vincent](https://blog.fsck.com) / [Prime Radiant](https://primeradiant.com);
this fork adapts it to DeepSeek Harness. It is not affiliated with or endorsed
by the Superpowers project, Prime Radiant, or DeepSeek.

[![tests](https://github.com/dkeviv/dsh-superpowers-verified/actions/workflows/tests.yml/badge.svg)](https://github.com/dkeviv/dsh-superpowers-verified/actions/workflows/tests.yml)

```
15 skills · DeepSeek Harness (DSH) · 86 tests · live-catalog verification · non-destructive install
```

**Keywords:** Superpowers fork for DeepSeek Harness · DSH skills ·
obra/superpowers port · DeepSeek coding agent skills · TDD · subagent-driven
development · agentic workflow for DSH · `superpowers-dsh` alternative ·
DeepSeek Harness 技能包 · 超级技能

## Install

```bash
git clone https://github.com/dkeviv/dsh-superpowers-verified.git
cd dsh-superpowers-verified
./bin/install.sh --dry-run     # see exactly what will change
./bin/install.sh
```

Then start a fresh DSH session and send `Let's make a react todo list`. A
working install invokes **brainstorming** and asks what you actually want
before writing any code.

**Uninstall reverses it exactly:**

```bash
./bin/install.sh --uninstall
```

## Why this fork exists

Superpowers' skills are mostly harness-neutral, but two things don't carry over
to DSH, and this fork supplies them:

**1. DSH has no session-start hook.** Upstream injects `using-superpowers` via a
`SessionStart` hook (Claude Code, Codex, Cursor, Gemini, Muse, Pi, …). DSH's
`dsh-hooks-*` packages *provide* hooks to other harnesses rather than consuming
them. DSH's equivalent channel is its user-global instruction file,
`$DSH_HOME/AGENTS.md`, loaded every turn of every session — so the bootstrap
goes there, inside self-managed markers.

**2. DSH has a different tool vocabulary.** Nothing here is named `Agent`,
`Task`, `TodoWrite`, or `Skill`. DSH provides `skill`, `todo_write`,
`subagent`/`subagent_fork`/`workflow`, native plan mode, and a file sandbox.
[`references/dsh-tools.md`](references/dsh-tools.md) is the translation layer.
Upstream's platform-adaptation list is rewritten to name DSH **only**: the
Claude Code reference file left in place describes nested-subagent depth tuning
and a `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` variable that do not exist here.

**3. DSH skill names carry no namespace.** Upstream cross-references its own
skills as `superpowers:writing-plans`, but DSH rejects a colon in a skill name
outright, so those references are unresolvable as written. See
[Known limitations](#known-limitations) — this is the one upstream
incompatibility this fork documents rather than silently patches.

## What makes this fork different

There are several Superpowers ports for DSH. This one is built around two
properties rather than around features:

**Verification against the real catalog, not against prose.** `bin/verify.sh`
mounts DSH's own skill registry and filesystem provider and asks what actually
resolves — then checks it. Around that, `tests/run.sh` is 86 checks covering
snapshot integrity, fidelity against the vendored copy, idempotency, hostile
`AGENTS.md` inputs, migration paths, and uninstall, plus a GitHub Actions matrix
on Ubuntu and macOS. Most ports *assert* DSH compatibility; this one
demonstrates it, and fails loudly when it does not hold.

**An install that cannot damage your setup.** The suite runs entirely in a
throwaway prefix, so it never touches your real skill root or `AGENTS.md`. The
installer owns only the region between its markers, preserves your own
`AGENTS.md` content, appends rather than reorders, and uninstalls exactly what
it installed. Updating means `git pull && ./bin/install.sh` — idempotent, so
running it twice is safe.

**A pinned, auditable snapshot.** The skills are a vendored copy of upstream at
an exact commit ([`vendor/superpowers/README.md`](vendor/superpowers/README.md)),
so installs are offline, reproducible, and diffable against upstream. All
DSH-specific code lives outside `vendor/`.

| | This fork | Typical DSH port |
| --- | --- | --- |
| Install mechanism | Filesystem installer into DSH's native skill roots | Cordis plugin bundle via `dsh plugin add` |
| Compatibility evidence | 86-check suite + live-catalog verifier + 2-OS CI | Prose assertion |
| Install reversibility | Marked-block ownership, exact uninstall | Varies |
| Upstream skills | Pinned commit, vendored | Usually synced at build time |

The plugin-bundle approach is more idiomatic to DSH's internals; the
filesystem approach needs no plugin layer and keeps every change reviewable in
your own config. Pick whichever fits how you run DSH.

## What you get

All 15 Superpowers skills:

| Skill | Purpose |
| --- | --- |
| `using-superpowers` | Entry point: how to find and use skills |
| `brainstorming` | Draw out intent before building |
| `writing-plans` | Break approved designs into bite-sized tasks |
| `executing-plans` | Inline plan execution, one review at the end |
| `subagent-driven-development` | Fresh subagent per task, reviewed |
| `dispatching-parallel-agents` | Fan independent work out in parallel |
| `systematic-debugging` | Root-cause discipline before fixes |
| `test-driven-development` | RED-GREEN-REFACTOR enforcement |
| `verification-before-completion` | Evidence before claims |
| `requesting-code-review` | Pre-merge review |
| `receiving-code-review` | Evaluate feedback on technical merit |
| `finishing-a-development-branch` | Integrate completed work safely |
| `using-git-worktrees` | Isolated workspaces |
| `writing-skills` | Author and test new skills |
| `diagnosing-superpowers` | Post-mortem a session from its transcript |

## Options

| Option | Effect |
| --- | --- |
| `--target <dir>` | Skill root (default `$DSH_AGENTS_HOME/skills` or `~/.agents/skills`) |
| `--dsh-home <dir>` | DSH home holding `AGENTS.md` (default `$DSH_HOME` or `~/.dsh`) |
| `--no-skills` / `--no-bootstrap` | Do just one half |
| `--dry-run` | Print intended changes, write nothing |
| `--uninstall` | Reverse the install |

## Verification

Two independent things, both re-runnable:

```bash
tests/run.sh          # 86 checks, offline, no writes outside a temp dir
bin/verify.sh         # audit a LIVE install against DSH's own skill catalog
```

`bin/verify.sh` is the interesting one. It does not read your files and guess —
it mounts DSH's real skill registry and filesystem provider in a bare Cordis
context (the same code the running harness uses), asks for the resolved
catalog, and checks the answers:

```bash
$ ./bin/verify.sh
Verifying Superpowers for DSH
  modules: /Users/you/.npm/_npx/…/node_modules
  skills:  /Users/you/.agents/skills
  AGENTS:  /Users/you/.dsh/AGENTS.md

  ✓ catalog resolves completely        22 skills
  ✓ every vendored skill resolves from --target   15/15 at …/.agents/skills
  ✓ no resolved skill name uses a namespace
  ✓ every installed skill has a loadable name
  ✓ no skill is shadowed by $DSH_HOME/skills
  ✓ DSH reference file installed
  ✓ adaptation list names DSH
  ✓ no other harness is advertised
  ✓ namespace workaround is documented
  ✓ bootstrap present in AGENTS.md     one balanced block
  ! upstream namespace references      46 references use superpowers:<name>; agents must strip the prefix

10 passed, 1 warnings, 0 failed
```

It exits non-zero when something is actually wrong, so it works in CI or a
pre-commit hook. It catches, among others: a skill that is installed but does
not resolve (including one silently skipped by DSH for an illegal name), a
skill shadowed by a higher-precedence root, a platform list that were reverted
to upstream, an unpaired bootstrap marker, and a missing reference file.

Options: `--target`, `--dsh-home`, `--modules <node_modules>`, `--json`. If it
cannot find the DSH packages, it says so and exits 2 rather than reporting a
misleading pass — set `DSH_NODE_MODULES` if auto-detection fails.

## Layout

```
bin/install.sh                     installer / uninstaller
bin/verify.sh                      audits a live install against the real catalog
lib/dsh-resolve-skills.mjs         mounts DSH's skill registry standalone
lib/session-start.sh               generates the bootstrap block
lib/patch-using-superpowers.mjs    rewrites the skill's platform-adaptation list
references/dsh-tools.md            the DSH harness reference (installed into the skill)
vendor/superpowers/                unmodified upstream snapshot (MIT, pinned commit)
tests/run.sh                       86-check end-to-end suite
docs/install.md                    install, update, troubleshooting notes
```

## Known limitations

- **Cross-skill references keep upstream's namespace prefix.** 41 references
  across 11 skill files read `superpowers:writing-plans` and so on. DSH's
  `isSkillName` rejects a colon, so `skill({name: "superpowers:writing-plans"})`
  fails with `invalid skill name`. This fork deliberately does **not** rewrite
  them: doing so means editing vendored skill bodies, which is exactly the kind
  of silent divergence that makes a fork untrustworthy on the next re-vendor.
  Instead the rule is documented in
  [`references/dsh-tools.md`](references/dsh-tools.md) — strip the prefix, load
  the bare name — so the agent resolves them without the files diverging. A
  wrapper script on `PATH` named `superpowers:writing-plans` would also absorb
  the colon, if you prefer a mechanism to a convention.
- **No worktree tool.** DSH has no managed git integration, so
  `using-git-worktrees` takes its `git worktree` fallback path. Under the
  `workspace-write` sandbox, create worktrees *inside* the workspace.
- **`diagnosing-superpowers` needs `zstd`.** DSH stores transcripts as
  `session.v4.jsonl.zstd`; session discovery can't read them without a
  decompressor. The layout and command are in
  [`references/dsh-tools.md`](references/dsh-tools.md).
- **Bootstrap is not re-injected after compaction.** The skill *catalog* is
  re-sent every turn, so skills keep working, but auto-triggering can fade deep
  into a very long session.
- **Vendored snapshot, not a live feed.** Skills update when you `git pull` and
  re-run the installer. See
  [`vendor/superpowers/README.md`](vendor/superpowers/README.md).

## Credits and license

MIT — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

The vendored skills in `vendor/superpowers/` are **Copyright (c) 2025 Jesse
Vincent**, MIT licensed, unmodified, reproduced at
[`vendor/superpowers/LICENSE`](vendor/superpowers/LICENSE). Superpowers is by
[Jesse Vincent](https://blog.fsck.com) and the team at
[Prime Radiant](https://primeradiant.com) — all of the methodology here is
theirs; this fork only adapts how it runs on DeepSeek Harness.

**Upstream:** https://github.com/obra/superpowers ·
[MIT](https://github.com/obra/superpowers/blob/main/LICENSE) ·
[Docs](https://github.com/obra/superpowers#readme) ·
[Discord](https://discord.gg/35wsABTejz)
