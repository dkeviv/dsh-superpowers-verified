# Fork information

`dsh-superpowers-verified` is a **fork of
[Superpowers](https://github.com/obra/superpowers) adapted for the
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH)**.

If you are looking for Superpowers itself, or for the harnesses it supports
officially, go upstream: **https://github.com/obra/superpowers**.

| | |
| --- | --- |
| Upstream project | [obra/superpowers](https://github.com/obra/superpowers) |
| Upstream version vendored | v7.0.0 |
| Upstream commit | `bb92a77741419a4ab5f06e711a283343f1ada0c3` |
| Upstream license | MIT, Copyright (c) 2025 Jesse Vincent |
| This fork's license | MIT (see [LICENSE](LICENSE)) |
| Target harness | DeepSeek Harness (DSH) only |
| Affiliation | None — independent community fork, not endorsed by Prime Radiant or DeepSeek |

## Fork or port?

Both descriptions are used for projects like this. Precisely:

- This repository **vendors an unmodified snapshot** of upstream's `skills/`
  and `LICENSE` (`vendor/superpowers/`). It does not GitHub-fork the upstream
  repository, and there is no shared Git history or parent-repo link.
- It **forks the methodology** in the sense you would expect: same skills, same
  workflow, adapted so it runs on a harness upstream does not target.

So "fork of Superpowers for DeepSeek Harness" is accurate. If you want the real
GitHub fork graph or to contribute back, use upstream.

## What this fork changes

Everything DSH-specific lives **outside** `vendor/`, so the diff against
upstream is small and auditable:

| Change | Where |
| --- | --- |
| Copy skills into DSH's native skill roots | `bin/install.sh` |
| Rewrite the skill's platform-adaptation list to name DSH only, and drop the other harnesses' reference files | `lib/patch-using-superpowers.mjs` |
| Generate the session bootstrap for `$DSH_HOME/AGENTS.md` | `lib/session-start.sh` |
| Verify a live install against DSH's real skill catalog | `bin/verify.sh`, `lib/dsh-resolve-skills.mjs` |
| Detect and repair a `npx skills update` clobber | `bin/install.sh --check` |
| Document DSH's tools, sandbox, and session storage | `references/dsh-tools.md` |

Nothing else upstream is modified — no skill body is rewritten, no skill is
dropped, and no upstream file is edited in place. Re-vendoring is a plain copy;
see [`vendor/superpowers/README.md`](vendor/superpowers/README.md).

## Why a fork instead of an upstream PR

Upstream states that it does not generally accept contributions of new skills,
and that any skill change must work across every harness it supports. DSH
support therefore lives here as an adapter rather than as a patch proposed
upstream. Upstream remains the source of truth for all methodology; if the two
ever disagree about what a skill *should* say, upstream is right and this fork
has a bug.

## Other Superpowers ports for DSH

This is not the only Superpowers adaptation for DeepSeek Harness, and it is not
the most widely used one. Notably:

- [LayneChai/superpowers-dsh](https://github.com/LayneChai/superpowers-dsh) —
  installs as a DSH Cordis plugin bundle (`dsh plugin add`), published on npm as
  `superpowers-dsh`.
- [Wenaixi/dsh-superpower](https://github.com/Wenaixi/dsh-superpower) — DSH
  plugin with bilingual skill descriptions and per-skill toggles.

This fork takes a different route: a filesystem installer into DSH's native
skill roots and instruction file, with no plugin layer, so every change it makes
is visible and revertible in your own config. If you prefer the plugin
mechanism, use one of the projects above.

## Trademarks and naming

"Superpowers" here refers to the upstream project by Jesse Vincent. This fork
is named `dsh-superpowers-verified` to keep it distinct from upstream and from
the other DSH ports. No endorsement or affiliation is claimed.
