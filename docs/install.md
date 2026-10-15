# Installation notes

Operational detail for `bin/install.sh`. For the short version, see the
[README](../README.md).

## Where things go

| What | Path | Override |
| --- | --- | --- |
| Skills | `$DSH_AGENTS_HOME/skills/<name>/` | `--target`, `$DSH_AGENTS_HOME` |
| Bootstrap | `$DSH_HOME/AGENTS.md` | `--dsh-home`, `$DSH_HOME` |

Defaults: `~/.agents/skills` and `~/.dsh/AGENTS.md`.

`~/.agents/skills` is the right default because DSH's filesystem skill provider
discovers it directly (`user-agents` root) along with `$DSH_HOME/skills`,
`<project>/.dsh/skills`, and `<project>/.agents/skills`. If a skill of the same
name exists in a higher-precedence root, that one wins — the installer prints
where it wrote so you can check for shadows.

## The bootstrap block

DSH loads `AGENTS.md` from `$DSH_HOME` as user-global instructions, plus
`AGENTS.md`/`CLAUDE.md` from the working tree and its ancestors. The block the
installer writes is delimited:

```
<!-- BEGIN dsh-superpowers-verified bootstrap -->
...
<!-- END dsh-superpowers-verified bootstrap -->
```

The installer **owns only what is between those markers**. Re-running replaces
that region and appends it at the end of the file if missing; everything you
wrote is preserved and is never reordered relative to the block. The block is
generated from the *installed* `using-superpowers/SKILL.md`, so it always
matches the skills actually on disk rather than a stale copy.

To remove it by hand, delete from `BEGIN` through `END` inclusive, or run
`./bin/install.sh --uninstall --no-skills`.

## Migrating from a hand-rolled bootstrap

If you previously installed the bootstrap manually (for example by running
upstream's `hooks/session-start` and pasting the output into `AGENTS.md`), there
is no marker for the installer to find. Left alone, it would *append* the
bootstrap rather than replace it, and the skill body would appear twice in every
session.

The installer handles this: if the file *opens* with a comment naming
`superpowers bootstrap` **and** contains the manual-removal hint
(`To remove Superpowers`), the leading block is stripped before the managed
block is written. Content after the legacy block is kept.

This check is deliberately narrow. A file that merely mentions the phrase
further down is not modified beyond the normal append.

## Coexisting with the `skills` CLI

`npx skills add obra/superpowers` and this installer both write to the same
skill root, and the `skills` CLI offers no hook to run after it writes. So if
you update Superpowers through the CLI, upstream's files replace this fork's
adaptation: the platform list reverts to all six harnesses, `references/dsh-tools.md`
is removed, and the other harnesses' reference files return. Measured, not
assumed — `npx skills update -g -y` does exactly that to a patched install.

Two ways to run this safely:

**Preferred — let the CLI update the other skills, then repair.** `./bin/install.sh`
detects the clobber, warns, and reapplies the adaptation:

```bash
npx skills update -g -y     # touches the other skills, strips our patch
./bin/install.sh            # warns "lost its DSH adaptation; repairing"
```

**Or check first, without writing**, for a hook or a health check:

```bash
./bin/install.sh --check
# needs repair: ~/.agents/skills/using-superpowers is missing the DSH adaptation
# cause: something reinstalled upstream over it, typically `npx skills update`
# fix:   ./bin/install.sh --target ~/.agents/skills
```

`--check` exits 1 when a repair is needed and 0 when the adaptation is intact,
so it can gate a commit hook or a scheduled check. `bin/verify.sh` reports the
same condition and includes the fix in its failure message.

Nothing is lost by the clobber beyond the adaptation itself: the skill bodies
are all upstream content, and the repair re-copies them from the pinned
snapshot. The bootstrap in `AGENTS.md` is unaffected, because the CLI does not
manage that file.

## Verifying an install

`bin/verify.sh` audits a live install against DSH's own skill catalog rather
than against assumptions. It mounts DSH's registry and filesystem provider in a
bare Cordis context, so it needs the DSH packages but does **not** need DSH to
be running:

```bash
./bin/verify.sh                       # defaults: ~/.agents/skills, ~/.dsh
./bin/verify.sh --target <dir> --dsh-home <dir>
./bin/verify.sh --modules <node_modules>   # if auto-detection fails
./bin/verify.sh --json                      # machine-readable
```

Exit status is 0 when every check passes (warnings allowed), 1 when a check
fails, and 2 for a usage or environment problem — for example when the DSH
packages cannot be found, which it reports rather than silently passing.

Set `DSH_NODE_MODULES` if the packages live somewhere unusual. Auto-detection
tries `npm root -g`, then the npx cache (`~/.npm/_npx/*/node_modules`), which is
where `npx @deepseek-ai/dsh` installs them.

## Troubleshooting

**Skills don't appear.** Confirm the skill directories landed where DSH looks:

```bash
ls ~/.agents/skills/ | head
```

Then check the session's skill catalog. DSH resolves skills per turn, so a
newly installed skill appears without restarting, but a *shadowed* skill will
not — look for the same name in `<project>/.dsh/skills`,
`<project>/.agents/skills`, and `$DSH_HOME/skills`.

**The agent doesn't use skills on its own.** The bootstrap is what makes that
happen. Verify it is present and current:

```bash
grep -c 'BEGIN dsh-superpowers-verified bootstrap' "${DSH_HOME:-$HOME/.dsh}/AGENTS.md"
```

Check that the file has no YAML/encoding damage from another tool, and that its
size is within DSH's instruction budget (`agent-instructions` defaults to 64 KiB,
which the ~3.8 KB block is far under).

**"sandbox: file access denied".** Unrelated to Superpowers, but it will show up
the first time a skill tries to write outside the workspace. That message is a
policy denial, not a transient error; don't retry around it. See
`references/dsh-tools.md`.

**`diagnosing-superpowers` can't read a session.** DSH transcripts are
zstd-compressed and need `zstd -dc`. The layout and command are in
`references/dsh-tools.md`.

## Re-vendoring upstream

See [`vendor/superpowers/README.md`](../vendor/superpowers/README.md). The
short version: replace `vendor/superpowers/skills/` and `LICENSE`, update the
pinned commit in that README, then run `tests/run.sh`. If upstream restructures
the platform-adaptation list, the patch script fails loudly rather than
silently installing a skill that never mentions DSH.
