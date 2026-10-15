# Vendored Superpowers snapshot

This directory contains an unmodified copy of the skill library from
[obra/superpowers](https://github.com/obra/superpowers), MIT licensed and
Copyright (c) 2025 Jesse Vincent. See `LICENSE` in this directory for the full
license text.

It is vendored rather than fetched at install time so that `superpowers-dsh`
installs a known-good, reviewable snapshot with no network access and no
dependence on an upstream branch moving underfoot.

```
source:   https://github.com/obra/superpowers.git
version:  7.0.0
commit:   bb92a77741419a4ab5f06e711a283343f1ada0c3
commitDate: 2026-10-09T17:28:04-07:00
subject:  Release v7.0.0: rebuilt brainstorming, Antigravity Marketplace manifest, Windows hook fixes (#2489)
vendored: skills/, LICENSE
```

## What was copied

`skills/` and `LICENSE`, byte-for-byte, via:

```bash
git clone --depth 1 https://github.com/obra/superpowers.git
cp -R superpowers/skills vendor/superpowers/skills
cp superpowers/LICENSE vendor/superpowers/LICENSE
```

Nothing in this directory is edited by hand, and the installer never mutates it.
All DSH-specific adaptation happens at install time, in the target directory —
see `lib/patch-using-superpowers.mjs`. That keeps the diff against upstream
auditable and makes re-vendoring a mechanical `cp`.

## Updating this snapshot

1. Clone upstream at the desired tag or commit.
2. Replace `skills/` and `LICENSE` wholesale; update the metadata above.
3. Run `tests/run.sh`. If upstream restructured `using-superpowers`'s
   platform-adaptation list, the patch script fails loudly — update its `ANCHOR`
   and reconcile `references/dsh-tools.md` with any new instructions upstream
   added for other harnesses.
4. Diff the vendored skills against the previous snapshot and skim for new
   harness-specific assumptions before trusting the test suite.

Upstream does not accept contributions of new skills and requires skill changes
to work across every harness it supports, so DSH support is carried here as an
adapter rather than as a patch proposed upstream.
