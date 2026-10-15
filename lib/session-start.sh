#!/usr/bin/env bash
# Emit Superpowers' DSH bootstrap block on stdout.
#
# Upstream Superpowers injects the full `using-superpowers` skill at session
# start via a `SessionStart` hook. DSH has no skill hook, so this adapter puts
# the same content in DSH's user-global instruction file ($DSH_HOME/AGENTS.md),
# which DSH loads on every turn of every session.
#
# Usage: lib/session-start.sh <installed-using-superpowers-skill-dir>
#
# Upstream's own hooks/session-start contains the same idea with per-harness
# JSON envelopes; we only need the raw text, so this is a small reimplementation
# rather than a copy. It reads the *installed* SKILL.md, so the bootstrap always
# matches the skills actually on disk.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <installed-using-superpowers-skill-dir>" >&2
  exit 2
fi

skill_dir="$1"
skill_md="${skill_dir}/SKILL.md"

if [ ! -r "$skill_md" ]; then
  echo "session-start: cannot read ${skill_md}" >&2
  exit 1
fi

# Bash builtin read; no PATH dependency (this may run in odd environments).
using_superpowers_content="$(<"$skill_md")"

# DSH's own tool for loading a skill is `skill`, and the catalog of every
# installed skill is already in the session context, so there is no `Skill`
# tool to point at. Rewrite that one sentence; the wording mirrors upstream.
using_superpowers_content="${using_superpowers_content//"For all other skills, use the 'Skill' tool:"/"The full catalog of installed skills is already in your session context; load any of them with DSH's \`skill\` tool by name."}"

printf '<EXTREMELY_IMPORTANT>\n'
printf 'You have superpowers.\n\n'
printf "**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use DSH's \`skill\` tool by name; the catalog is in your session context:**\n\n"
printf '%s\n' "$using_superpowers_content"
printf '</EXTREMELY_IMPORTANT>\n'
