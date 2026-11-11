# dsh-superpowers-verified

**A fork of [Superpowers](https://github.com/obra/superpowers) for the [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH)** — the full Superpowers methodology (brainstorming, planning, TDD, systematic debugging, subagent-driven execution) adapted to run on DSH, installed **verifiably and reversibly**.

Superpowers is an agentic software-development methodology by [Jesse Vincent](https://blog.fsck.com) / [Prime Radiant](https://primeradiant.com); this fork adapts it to DeepSeek Harness. It is not affiliated with or endorsed by the Superpowers project, Prime Radiant, or DeepSeek.

[![tests](https://github.com/dkeviv/dsh-superpowers-verified/actions/workflows/tests.yml/badge.svg)](https://github.com/dkeviv/dsh-superpowers-verified/actions/workflows/tests.yml)

```
15 skills · DeepSeek Harness (DSH) · 111 tests · live-catalog verification · non-destructive install
```

---

## What This Plugin Does

This plugin brings the **Superpowers methodology** to DeepSeek Harness (DSH). It provides 15 skills that guide you through the entire software development lifecycle:

| Skill | Purpose |
|-------|---------|
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

---

## Installation Methods

### Method 1: Via DSH Plugins Page (Recommended) 🎯

This is the easiest way — install directly from the DSH desktop app's Plugins page.

1. Open the DSH desktop app
2. Open **Settings → Plugins** (or click the puzzle piece icon in the sidebar)
3. Click **Add plugin**
4. Enter: `github:dkeviv/dsh-superpowers-verified`
4. Click **Install**, then **Enable now**
5. Restart the app if prompted

The plugin will:
- Register all 15 Superpowers skills in the skill catalog
- Inject the bootstrap into every session (so Superpowers is active from turn 1)
- Add the DSH tool reference (`references/dsh-tools.md`)

### Method 2: CLI (for automation)

```bash
# Install from GitHub (latest main branch)
dsh plugin --profile desktop add github:dkeviv/dsh-superpowers-verified

# Or install from npm (when published)
dsh plugin --profile desktop add @dkeviv/dsh-superpowers-verified

# List installed plugins
dsh plugin --profile desktop list
```

### Method 3: Shell Installer (Manual, No Plugin System)

If you prefer not to use the plugin system, or want a non-plugin installation:

```bash
git clone https://github.com/dkeviv/dsh-superpowers-verified.git
cd dsh-superpowers-verified
./bin/install.sh --dry-run    # Preview changes
./bin/install.sh              # Install
```

This installs skills to `~/.agents/skills` and writes a bootstrap block to `~/.dsh/AGENTS.md`. Uninstall with `./bin/install.sh --uninstall`.

---

## Verification

Two independent verification methods:

```bash
# 1. Run the full test suite (111 tests)
./tests/run.sh

# 2. Verify a live install against DSH's actual catalog
./bin/verify.sh
```

The verifier mounts DSH's real skill registry and checks that all 15 skills resolve correctly, the bootstrap is present in AGENTS.md, and no namespace conflicts exist.

---

## What Makes This Fork Different

| Feature | This Fork | Typical DSH Port |
|---------|-----------|------------------|
| **Install mechanism** | DSH Plugin (Plugins page) + Shell installer | Usually just one method |
| **Verification** | 111 tests + live catalog verifier | Usually just prose |
| **Install reversibility** | Exact uninstall, marked-block ownership | Varies |
| **Upstream sync** | Pinned commit, vendored, reproducible | Often synced at build time |
| **Evidence** | 111 tests + live catalog verification | Usually just claims |

---

## Two Installation Modes (Pick One)

### 🎯 Plugin Mode (Recommended for DSH Desktop App)
- Installs via **Settings → Plugins → Add plugin**
- Skills registered in DSH's skill catalog (available via `/` menu)
- Bootstrap injected automatically every session via system prompt
- Updates via `dsh plugin update` or Plugins page

### 🛠 Shell Installer Mode (No Plugin System Required)
```bash
git clone https://github.com/dkeviv/dsh-superpowers-verified.git
cd dsh-superpowers-verified
./bin/install.sh --dry-run   # Preview
./bin/install.sh             # Install
```
- Installs skills to `~/.agents/skills` (real directories)
- Writes bootstrap to `~/.dsh/AGENTS.md` (loaded every session)
- Reversible: `./bin/install.sh --uninstall`
- Skills also available via DSH's skill catalog if `~/.agents/skills` is in your skill roots

---

## Verification

```bash
# Run all 111 tests (runs in throwaway dirs, no side effects)
tests/run.sh

# Verify a live installation against DSH's actual skill registry
bin/verify.sh
```

Sample `verify.sh` output:
```
$ ./bin/verify.sh
Verifying Superpowers for DSH
  ✓ catalog resolves completely        22 skills
  ✓ every vendored skill resolves       15/15
  ✓ no resolved skill name uses a namespace
  ✓ bootstrap present in AGENTS.md
  ✓ platform list names DSH only
  10 passed, 1 warnings, 0 failed
```

---

## Layout

```
bin/install.sh          # Shell installer / uninstaller (method 2)
bin/verify.sh           # Live install verifier
index.js                # DSH plugin entry point (registers skills + bootstrap)
cordis.patch.yml        # DSH plugin bundle patch (for Plugins page)
lib/
  session-start.sh      # Generates bootstrap block for AGENTS.md
  patch-using-superpowers.mjs  # Rewrites platform-adaptation list for DSH
references/
  dsh-tools.md          # DSH tool mapping (installed into skill)
vendor/superpowers/skills/   # 15 vendored Superpowers skills (pinned commit)
tests/run.sh            # 111 end-to-end tests
docs/install.md         # Detailed install notes
```

---

## Known Limitations

1. **`npx skills update` strips DSH adaptation** — The `skills` CLI is a second owner of `~/.agents/skills`. Re-running `./bin/install.sh` repairs it. Use `./bin/install.sh --check` to detect.
2. **Cross-skill references use upstream namespace** — 41 references use `superpowers:writing-plans` format. DSH rejects colons in skill names. Strip the prefix when invoking (documented in `references/dsh-tools.md`).
3. **`diagnosing-superpowers` needs `zstd`** for reading DSH transcripts.
4. **Bootstrap not re-injected after compaction** — Skills keep working, but auto-triggering can fade in very long sessions.
3. **Vendored snapshot** — Skills update when you `git pull && ./bin/install.sh`.

---

## Credits & License

**MIT License** — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

The vendored skills in `vendor/superpowers/` are **Copyright (c) 2025 Jesse Vincent**, MIT licensed, unmodified, reproduced at [`vendor/superpowers/LICENSE`](vendor/superpowers/LICENSE).

Superpowers is by [Jesse Vincent](https://blog.fsck.com) and the team at [Prime Radiant](https://primeradiant.com) — all methodology is theirs; this fork only adapts it for DSH.

**Upstream:** https://github.com/obra/superpowers · [MIT](https://github.com/obra/superpowers/blob/main/LICENSE) · [Docs](https://github.com/obra/superpowers#readme) · [Discord](https://discord.gg/35wsABTejz)

---

## Quick Start Summary

```bash
# Option 1: Plugins Page (easiest)
# Settings → Plugins → Add plugin → github:dkeviv/dsh-superpowers-verified → Enable

# Option 2: CLI
dsh plugin --profile desktop add github:dkeviv/dsh-superpowers-verified

# Option 3: Shell installer
git clone https://github.com/dkeviv/dsh-superpowers-verified.git
cd dsh-superpowers-verified && ./bin/install.sh

# Then start a fresh DSH session and type:
# "Let's make a react todo list"
# → brainstorming skill will activate and ask what you actually want to build
```
