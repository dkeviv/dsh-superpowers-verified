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

# Every DSH adaptation of the SKILL.md body belongs to
# lib/patch-using-superpowers.mjs (platform list, tool mapping); this emitter
# only wraps what it reads. Upstream's Platform Adaptation list names other
# harnesses by design and the patch owns rewriting it - the dry-run preview
# even reads the vendored, unpatched copy - so that one list is stripped
# before scanning. Anything else naming Claude Code's own tools means the
# patch and this emitter have drifted apart - fail loudly rather than ship
# instructions for tools DSH does not have.
adapted_content="$(printf '%s\n' "$using_superpowers_content" | awk '
  /^If your harness appears here, read its reference file for special instructions:$/ { skip = 1; next }
  skip && (/^$/ || /^- /) { next }
  skip { skip = 0 }
  { print }
')"
if printf '%s' "$adapted_content" | grep -qE "use the 'Skill' tool|TodoWrite|Task tool|claude-code-tools\.md"; then
  echo "session-start: the SKILL.md body still names Claude Code tools that DSH does not have." >&2
  echo "session-start: lib/patch-using-superpowers.mjs and this emitter have drifted apart;" >&2
  echo "session-start: extend the patch (and references/dsh-tools.md) before installing." >&2
  exit 1
fi

printf '<EXTREMELY_IMPORTANT>\n'
printf 'You have superpowers.\n\n'
printf "**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use DSH's \`skill\` tool by name; the catalog is in your session context:**\n\n"
printf '%s\n' "$using_superpowers_content"
printf '</EXTREMELY_IMPORTANT>\n'
