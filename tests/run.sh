#!/usr/bin/env bash
# End-to-end tests for dsh-superpowers-verified.
#
# Everything runs against a throwaway prefix, so the suite never touches a real
# ~/.agents/skills or ~/.dsh/AGENTS.md.
#
# Usage: tests/run.sh [-v]
set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly INSTALL="${REPO_ROOT}/bin/install.sh"
readonly VENDOR_SKILLS="${REPO_ROOT}/vendor/superpowers/skills"
readonly UPSTREAM_SKILL_COUNT=15

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else no "$desc" "command failed: $*"; fi
}
check_eq() { # check_eq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
readonly WORK

fresh_prefix() { # fresh_prefix <name> -> echo "skills_dir dsh_home"
  local root="${WORK}/$1"
  rm -rf "$root"
  mkdir -p "${root}/agents" "${root}/dshhome"
  printf '%s %s\n' "${root}/agents/skills" "${root}/dshhome"
}

# ---------------------------------------------------------------------------
section "1. Vendored snapshot"

check_eq "vendors exactly ${UPSTREAM_SKILL_COUNT} skills" \
  "$UPSTREAM_SKILL_COUNT" "$(find "$VENDOR_SKILLS" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
check "carries the upstream MIT license" test -f "${REPO_ROOT}/vendor/superpowers/LICENSE"
check "records provenance (commit + version)" test -f "${REPO_ROOT}/vendor/superpowers/README.md"
check "provenance pins an immutable commit" \
  grep -qE '^[[:space:]]*commit:[[:space:]]+[0-9a-f]{40}[[:space:]]*$' "${REPO_ROOT}/vendor/superpowers/README.md"
check "provenance records the upstream version" \
  grep -qE '^[[:space:]]*version:[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' "${REPO_ROOT}/vendor/superpowers/README.md"

bad_frontmatter=0
for d in "$VENDOR_SKILLS"/*/; do
  name="$(basename "$d")"
  [ -f "${d}SKILL.md" ] || { bad_frontmatter=1; continue; }
  fm_name="$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); gsub(/"/, ""); print; exit}' "${d}SKILL.md")"
  [ "$fm_name" = "$name" ] || bad_frontmatter=1
done
check_eq "every skill's frontmatter name matches its directory" "0" "$bad_frontmatter"

exec_count="$(find "$VENDOR_SKILLS" -type f -perm -u+x | wc -l | tr -d ' ')"
check "vendored scripts kept their executable bit (${exec_count} found)" \
  test "$exec_count" -ge 9

# ---------------------------------------------------------------------------
section "2. Skill installation"

read -r SKILLS DSHHOME <<<"$(fresh_prefix install)"
"$INSTALL" --target "$SKILLS" --dsh-home "$DSHHOME" >/dev/null 2>&1
install_rc=$?
check_eq "installer exits 0" "0" "$install_rc"

check_eq "installs all ${UPSTREAM_SKILL_COUNT} skills" \
  "$UPSTREAM_SKILL_COUNT" "$(find "$SKILLS" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"

exec_installed="$(find "$SKILLS" -type f -perm -u+x | wc -l | tr -d ' ')"
check_eq "installed scripts are still executable" "$exec_count" "$exec_installed"

# Content fidelity: identical to vendored, except using-superpowers (patched).
drift=0
for d in "$VENDOR_SKILLS"/*/; do
  name="$(basename "$d")"
  [ "$name" = "using-superpowers" ] && continue
  diff -r "$d" "${SKILLS}/${name}" >/dev/null 2>&1 || drift=1
done
check_eq "non-patched skills are byte-identical to the snapshot" "0" "$drift"

check "installs the DSH platform reference" \
  test -f "${SKILLS}/using-superpowers/references/dsh-tools.md"
check "reference file is non-trivial" \
  test "$(wc -c < "${SKILLS}/using-superpowers/references/dsh-tools.md" | tr -d ' ')" -gt 2000
check "points at DSH in the platform-adaptation section" \
  grep -qF -- '- DeepSeek Harness (DSH): `references/dsh-tools.md`' "${SKILLS}/using-superpowers/SKILL.md"

# An agent that follows claude-code-tools.md reaches for Task/TodoWrite, which
# do not exist on DSH. Only the DSH reference file may be advertised.
check "names no other harness in the adaptation list" \
  bash -c "! grep -qE '^- (Claude Code|Codex|Pi|Antigravity|Hermes Agent|Muse):' '${SKILLS}/using-superpowers/SKILL.md'"
check "ships only the DSH and claude-code reference files" \
  bash -c "cd '${SKILLS}/using-superpowers/references' && [ \"\$(ls *.md | sort | tr '\n' ' ')\" = 'claude-code-tools.md dsh-tools.md ' ]"
check "the upstream harness reference files are gone" \
  test ! -f "${SKILLS}/using-superpowers/references/muse-tools.md"

# The patch must be surgical: only the platform-adaptation list may change.
# Comparing line counts is misleading — removing lines shifts numbering, so
# identical trailing lines show up as additions. Compare surviving content
# directly instead: the body before the list, and everything after it.
check "the skill body before the adaptation list is untouched" \
  bash -c "diff <(sed -n '1,53p' '${VENDOR_SKILLS}/using-superpowers/SKILL.md') <(sed -n '1,53p' '${SKILLS}/using-superpowers/SKILL.md') >/dev/null"
check "everything after the adaptation list is untouched" \
  bash -c "v=\$(awk '/^## User Instructions/{print NR; exit}' '${VENDOR_SKILLS}/using-superpowers/SKILL.md'); i=\$(awk '/^## User Instructions/{print NR; exit}' '${SKILLS}/using-superpowers/SKILL.md'); diff <(sed -n \"\${v},\\\$p\" '${VENDOR_SKILLS}/using-superpowers/SKILL.md') <(sed -n \"\${i},\\\$p\" '${SKILLS}/using-superpowers/SKILL.md') >/dev/null"

# ---------------------------------------------------------------------------
section "3. Idempotency"

before="$(cat "${SKILLS}/using-superpowers/SKILL.md")"
"$INSTALL" --target "$SKILLS" --dsh-home "$DSHHOME" >/dev/null 2>&1
check_eq "second install changes nothing" "$before" "$(cat "${SKILLS}/using-superpowers/SKILL.md")"
check_eq "second install does not duplicate the DSH bullet" "1" \
  "$(grep -cF -- '- DeepSeek Harness (DSH): `references/dsh-tools.md`' "${SKILLS}/using-superpowers/SKILL.md")"
check_eq "second install does not duplicate the bootstrap block" "1" \
  "$(grep -cF 'BEGIN dsh-superpowers-verified bootstrap' "${DSHHOME}/AGENTS.md")"

# A third run after deleting one skill restores it.
rm -rf "${SKILLS}/writing-plans"
"$INSTALL" --target "$SKILLS" --dsh-home "$DSHHOME" >/dev/null 2>&1
check "restores a deleted skill" test -f "${SKILLS}/writing-plans/SKILL.md"

# ---------------------------------------------------------------------------
section "4. Bootstrap block"

AGENTS_MD="${DSHHOME}/AGENTS.md"
check "writes the bootstrap to \$DSH_HOME/AGENTS.md" test -f "$AGENTS_MD"
check "block is delimited by markers" \
  bash -c "grep -qF 'BEGIN dsh-superpowers-verified bootstrap' '$AGENTS_MD' && grep -qF 'END dsh-superpowers-verified bootstrap' '$AGENTS_MD'"
check "contains Superpowers' activation preamble" grep -qF 'You have superpowers.' "$AGENTS_MD"
check "contains the full using-superpowers body" grep -qF 'Red Flags' "$AGENTS_MD"
check "points at DSH's skill tool, not a Skill tool" \
  bash -c "grep -qF \"DSH's \\\`skill\\\` tool\" '$AGENTS_MD' && ! grep -qF \"use the 'Skill' tool\" '$AGENTS_MD'"

# Markers must be well-ordered and the block last.
check "BEGIN precedes END" \
  bash -c "[ \"\$(grep -nF 'BEGIN dsh-superpowers-verified bootstrap' '$AGENTS_MD' | cut -d: -f1)\" -lt \"\$(grep -nF 'END dsh-superpowers-verified bootstrap' '$AGENTS_MD' | cut -d: -f1)\" ]"

# Foreign content in AGENTS.md must survive a reinstall.
printf '# My own global instructions\n\nAlways use tabs.\n' | cat - "$AGENTS_MD" > "${AGENTS_MD}.tmp" && mv "${AGENTS_MD}.tmp" "$AGENTS_MD"
"$INSTALL" --target "$SKILLS" --dsh-home "$DSHHOME" >/dev/null 2>&1
check "preserves user content that precedes the block" \
  grep -qF 'Always use tabs.' "$AGENTS_MD"
check_eq "still exactly one block after reinstall over user content" "1" \
  "$(grep -cF 'BEGIN dsh-superpowers-verified bootstrap' "$AGENTS_MD")"
check "user content stays above the block" \
  bash -c "[ \"\$(grep -nF 'Always use tabs.' '$AGENTS_MD' | cut -d: -f1)\" -lt \"\$(grep -nF 'BEGIN dsh-superpowers-verified bootstrap' '$AGENTS_MD' | cut -d: -f1)\" ]"

# ---------------------------------------------------------------------------
section "5. Options"

read -r S2 H2 <<<"$(fresh_prefix no_bootstrap)"
"$INSTALL" --target "$S2" --dsh-home "$H2" --no-bootstrap >/dev/null 2>&1
check "--no-bootstrap skips AGENTS.md" test ! -f "${H2}/AGENTS.md"
check "--no-bootstrap still installs skills" test -f "${S2}/brainstorming/SKILL.md"

read -r S3 H3 <<<"$(fresh_prefix no_skills)"
"$INSTALL" --target "$S3" --dsh-home "$H3" --no-skills >/dev/null 2>&1
check "--no-skills installs no skills" test ! -d "${S3}/brainstorming"
check "--no-skills reports the bootstrap prerequisite" test ! -f "${H3}/AGENTS.md"

read -r S4 H4 <<<"$(fresh_prefix dry_run)"
"$INSTALL" --target "$S4" --dsh-home "$H4" --dry-run >/dev/null 2>&1
check "--dry-run writes no skills" test ! -d "${S4}/brainstorming"
check "--dry-run writes no AGENTS.md" test ! -f "${H4}/AGENTS.md"

read -r S5 H5 <<<"$(fresh_prefix badflag)"
if "$INSTALL" --target "$S5" --dsh-home "$H5" --nonsense >/dev/null 2>&1; then
  no "rejects an unknown option" "exited 0"
else
  ok "rejects an unknown option"
fi
if "$INSTALL" --target >/dev/null 2>&1; then
  no "rejects an option missing its value" "exited 0"
else
  ok "rejects an option missing its value"
fi
check "--help exits 0" "$INSTALL" --help

# ---------------------------------------------------------------------------
section "6. Uninstall"

read -r S6 H6 <<<"$(fresh_prefix uninstall)"
"$INSTALL" --target "$S6" --dsh-home "$H6" >/dev/null 2>&1
printf '# Keep me\n' | cat - "${H6}/AGENTS.md" > "${H6}/AGENTS.md.tmp" && mv "${H6}/AGENTS.md.tmp" "${H6}/AGENTS.md"
"$INSTALL" --target "$S6" --dsh-home "$H6" --uninstall >/dev/null 2>&1
check_eq "removes every installed skill" "0" \
  "$(find "$S6" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
check "removes the bootstrap block" \
  bash -c "! grep -qF 'superpowers-verified bootstrap' '${H6}/AGENTS.md'"
check "keeps user content in AGENTS.md" grep -qF 'Keep me' "${H6}/AGENTS.md"
check "keeps an unrelated skill in the target root" \
  bash -c "mkdir -p '$S6/my-own-skill' && '$INSTALL' --target '$S6' --dsh-home '$H6' >/dev/null 2>&1 && '$INSTALL' --target '$S6' --dsh-home '$H6' --uninstall >/dev/null 2>&1 && [ -d '$S6/my-own-skill' ]"

# ---------------------------------------------------------------------------
section "7. Migration from a pre-markers install"

# Regression: an earlier bootstrap had no markers and lived at the top of
# AGENTS.md. Installing over it must replace it, not duplicate the skill body —
# a duplicate ships the whole skill twice to every session.
read -r S7 H7 <<<"$(fresh_prefix migrate)"
mkdir -p "$H7"
{
  printf '<!-- superpowers bootstrap (installed by DSH session session-legacy) -->\n'
  printf '<!-- To remove Superpowers'"'"' auto-activation: delete this file or this block. -->\n'
  printf '<EXTREMELY_IMPORTANT>\n'
  printf 'You have superpowers.\n\n'
  printf '**Below is the full content of your superpowers:using-superpowers skill - for other skills, use the '"'"'Skill'"'"' tool:**\n\n'
  printf -- '---\nname: using-superpowers\ndescription: legacy copy\n---\n\n'
  printf 'LEGACY-BODY-MARKER\n'
  printf '</EXTREMELY_IMPORTANT>\n\n'
  printf '# User content after the legacy block\n\nUse tabs.\n'
} > "${H7}/AGENTS.md"

"$INSTALL" --target "$S7" --dsh-home "$H7" >/dev/null 2>&1
check "removes the legacy unmarked block" \
  bash -c "! grep -qF 'LEGACY-BODY-MARKER' '${H7}/AGENTS.md'"
check "keeps content that followed the legacy block" \
  grep -qF 'Use tabs.' "${H7}/AGENTS.md"
check_eq "ends with exactly one managed block" "1" \
  "$(grep -cF 'BEGIN dsh-superpowers-verified bootstrap' "${H7}/AGENTS.md")"
check_eq "contains exactly one copy of the skill body" "1" \
  "$(grep -cF 'You have superpowers.' "${H7}/AGENTS.md")"
check_eq "contains exactly one closing tag" "1" \
  "$(grep -cF '</EXTREMELY_IMPORTANT>' "${H7}/AGENTS.md")"
check "user content survives above the block" \
  bash -c "[ \"\$(grep -nF 'Use tabs.' '${H7}/AGENTS.md' | cut -d: -f1)\" -lt \"\$(grep -nF 'BEGIN dsh-superpowers-verified bootstrap' '${H7}/AGENTS.md' | cut -d: -f1)\" ]"

# A file that merely mentions the phrase further down must not be touched.
read -r S8 H8 <<<"$(fresh_prefix notlegacy)"
mkdir -p "$H8"
printf '# Notes\n\nI once read about a superpowers bootstrap for DSH.\n\nKeep me.\n' > "${H8}/AGENTS.md"
"$INSTALL" --target "$S8" --dsh-home "$H8" >/dev/null 2>&1
check "leaves a non-leading mention of the phrase alone" \
  grep -qF 'I once read about a superpowers bootstrap' "${H8}/AGENTS.md"
check "still appends the managed block below user notes" \
  grep -qF 'BEGIN dsh-superpowers-verified bootstrap' "${H8}/AGENTS.md"

# Regression: this project was called `superpowers-dsh` before it was renamed,
# and that marker is sitting in real AGENTS.md files. Upgrading must replace the
# block in place rather than appending a second copy of the whole skill body.
# The fixture mirrors the real pre-rename output, including the `Managed by`
# comment *inside* the block, which is what the old installer wrote.
read -r S9 H9 <<<"$(fresh_prefix renamed)"
mkdir -p "$H9"
{
  printf '# User notes\n\nKeep me.\n\n'
  printf '<!-- BEGIN superpowers-dsh bootstrap -->\n'
  printf '<!-- Managed by superpowers-dsh. Regenerated by bin/install.sh; edits here are overwritten. -->\n'
  printf '<!-- Make Superpowers active from the first turn of every DSH session. -->\n'
  printf '<!-- Remove with: bin/install.sh --uninstall -->\n'
  printf '<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\nPRE-RENAME-BODY\n</EXTREMELY_IMPORTANT>\n'
  printf '<!-- END superpowers-dsh bootstrap -->\n'
} > "${H9}/AGENTS.md"

"$INSTALL" --target "$S9" --dsh-home "$H9" >/dev/null 2>&1
check "replaces the pre-rename block in place" \
  bash -c "! grep -qF 'PRE-RENAME-BODY' '${H9}/AGENTS.md'"
check_eq "leaves exactly one block after the rename" "1" \
  "$(grep -cF 'BEGIN dsh-superpowers-verified bootstrap' "${H9}/AGENTS.md")"
check_eq "no stale pre-rename marker survives" "0" \
  "$(grep -cF 'BEGIN superpowers-dsh bootstrap' "${H9}/AGENTS.md")"
check "writes the new marker" \
  grep -qF 'BEGIN dsh-superpowers-verified bootstrap' "${H9}/AGENTS.md"
check "preserves user notes during the rename" \
  grep -qF 'Keep me.' "${H9}/AGENTS.md"

# Uninstall must also work against a pre-rename install.
read -r S10 H10 <<<"$(fresh_prefix renamed_uninstall)"
mkdir -p "$H10"
printf '# Begin\n<!-- BEGIN superpowers-dsh bootstrap -->\nBODY\n<!-- END superpowers-dsh bootstrap -->\n' > "${H10}/AGENTS.md"
"$INSTALL" --target "$S10" --dsh-home "$H10" --uninstall >/dev/null 2>&1
check "uninstall recognizes the pre-rename marker" \
  bash -c "! grep -qF 'superpowers-dsh bootstrap' '${H10}/AGENTS.md'"
check "uninstall keeps user content from a pre-rename install" \
  grep -qF '# Begin' "${H10}/AGENTS.md"

# ---------------------------------------------------------------------------
section "8. Hostile inputs (regressions)"

# An unpaired BEGIN previously made the stripper swallow the rest of the file,
# silently deleting user content. The file must survive, with a warning.
read -r S11 H11 <<<"$(fresh_prefix orphan)"
mkdir -p "$H11"
printf 'top\n<!-- BEGIN dsh-superpowers-verified bootstrap -->\nMUST SURVIVE ONE\nMUST SURVIVE TWO\n' > "${H11}/AGENTS.md"
"$INSTALL" --target "$S11" --dsh-home "$H11" >/dev/null 2>&1
check_eq "orphan BEGIN keeps every following line" "2" "$(grep -c 'MUST SURVIVE' "${H11}/AGENTS.md")"
check "orphan BEGIN keeps content above it" grep -qF 'top' "${H11}/AGENTS.md"
check "orphan BEGIN is reported as a warning" \
  bash -c "'${INSTALL}' --target '${S11}' --dsh-home '${H11}' 2>&1 >/dev/null | grep -qF 'unpaired marker'"

# An unpaired END must not be treated as the end of a block that never opened.
read -r S12 H12 <<<"$(fresh_prefix orphanend)"
mkdir -p "$H12"
printf 'keep-a\n<!-- END dsh-superpowers-verified bootstrap -->\nkeep-b\n' > "${H12}/AGENTS.md"
"$INSTALL" --target "$S12" --dsh-home "$H12" >/dev/null 2>&1
check "orphan END keeps the file's content" \
  bash -c "grep -qF 'keep-a' '${H12}/AGENTS.md' && grep -qF 'keep-b' '${H12}/AGENTS.md'"

# Install/uninstall must round-trip exactly: no blank-line drift.
read -r S13 H13 <<<"$(fresh_prefix roundtrip)"
mkdir -p "$H13"
printf 'alpha\n\nbeta\n' > "${H13}/AGENTS.md"
original="$(cat "${H13}/AGENTS.md")"
for _ in 1 2 3; do
  "$INSTALL" --target "$S13" --dsh-home "$H13" >/dev/null 2>&1
  "$INSTALL" --target "$S13" --dsh-home "$H13" --uninstall >/dev/null 2>&1
done
check_eq "three install/uninstall cycles are a no-op" "$original" "$(cat "${H13}/AGENTS.md")"

# Replacing the file must not loosen its permissions.
read -r S14 H14 <<<"$(fresh_prefix perms)"
mkdir -p "$H14"
printf 'secret\n' > "${H14}/AGENTS.md"
chmod 600 "${H14}/AGENTS.md"
"$INSTALL" --target "$S14" --dsh-home "$H14" >/dev/null 2>&1
mode="$(stat -f '%Lp' "${H14}/AGENTS.md" 2>/dev/null || stat -c '%a' "${H14}/AGENTS.md" 2>/dev/null)"
check_eq "a 0600 AGENTS.md stays 0600" "600" "$mode"
check "the block was still written" grep -qF 'BEGIN dsh-superpowers-verified' "${H14}/AGENTS.md"

# A symlinked AGENTS.md must stay a symlink and be updated through it.
read -r S15 H15 <<<"$(fresh_prefix symlink)"
mkdir -p "$H15" "$WORK/dotfiles"
printf 'real content\n' > "$WORK/dotfiles/AGENTS.md"
ln -s "$WORK/dotfiles/AGENTS.md" "${H15}/AGENTS.md"
"$INSTALL" --target "$S15" --dsh-home "$H15" >/dev/null 2>&1
check "a symlinked AGENTS.md is still a symlink" test -L "${H15}/AGENTS.md"
check "the symlink target received the block" \
  grep -qF 'BEGIN dsh-superpowers-verified' "$WORK/dotfiles/AGENTS.md"
check "the symlink target kept its content" grep -qF 'real content' "$WORK/dotfiles/AGENTS.md"

# A file with no trailing newline must not have its last line joined.
read -r S16 H16 <<<"$(fresh_prefix nonewline)"
mkdir -p "$H16"
printf 'no newline at end' > "${H16}/AGENTS.md"
"$INSTALL" --target "$S16" --dsh-home "$H16" >/dev/null 2>&1
check "no-trailing-newline file keeps its last line intact" \
  grep -qxF 'no newline at end' "${H16}/AGENTS.md"

# ---------------------------------------------------------------------------
section "9. Bootstrap generator"

gen="$(bash "${REPO_ROOT}/lib/session-start.sh" "${SKILLS}/using-superpowers" 2>/dev/null)"
check "generator exits 0 and produces output" test -n "$gen"
check "wraps content in the activation preamble" \
  bash -c "printf '%s' \"\$1\" | grep -qF '<EXTREMELY_IMPORTANT>'" _ "$gen"
check "ends with the closing tag" \
  bash -c "printf '%s' \"\$1\" | tail -1 | grep -qF '</EXTREMELY_IMPORTANT>'" _ "$gen"
check "fails loudly on a missing skill dir" \
  bash -c "! bash '${REPO_ROOT}/lib/session-start.sh' '${WORK}/does-not-exist' 2>/dev/null"
check "refuses to run without an argument" \
  bash -c "! bash '${REPO_ROOT}/lib/session-start.sh' 2>/dev/null"

# ---------------------------------------------------------------------------
section "10. Patch script robustness"

check "patch script fails on a missing skill dir" \
  bash -c "! node '${REPO_ROOT}/lib/patch-using-superpowers.mjs' '${WORK}/nope' 2>/dev/null"
check "patch script fails on a restructured SKILL.md instead of silently skipping" \
  bash -c "d='${WORK}/restructured'; mkdir -p \"\$d\"; printf -- '---\nname: using-superpowers\ndescription: x\n---\n\nNo platform list here.\n' > \"\$d/SKILL.md\"; ! node '${REPO_ROOT}/lib/patch-using-superpowers.mjs' \"\$d\" 2>/dev/null"

# ---------------------------------------------------------------------------
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
