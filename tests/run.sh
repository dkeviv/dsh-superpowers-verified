#!/usr/bin/env bash
# End-to-end tests for superpowers-dsh.
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
check "registers DSH in the platform-adaptation list" \
  grep -qF 'DeepSeek Harness (DSH): `references/dsh-tools.md`' "${SKILLS}/using-superpowers/SKILL.md"
check "leaves the other harnesses' bullets intact" \
  grep -qF 'Muse: `references/muse-tools.md`' "${SKILLS}/using-superpowers/SKILL.md"

# The patch must be surgical: no unrelated edits to the upstream skill body.
diff_count="$(diff "${VENDOR_SKILLS}/using-superpowers/SKILL.md" \
  "${SKILLS}/using-superpowers/SKILL.md" | grep -cE '^[<>]' || true)"
check_eq "patch adds exactly one line to SKILL.md" "1" "$diff_count"

# ---------------------------------------------------------------------------
section "3. Idempotency"

before="$(cat "${SKILLS}/using-superpowers/SKILL.md")"
"$INSTALL" --target "$SKILLS" --dsh-home "$DSHHOME" >/dev/null 2>&1
check_eq "second install changes nothing" "$before" "$(cat "${SKILLS}/using-superpowers/SKILL.md")"
check_eq "second install does not duplicate the DSH bullet" "1" \
  "$(grep -cF 'DeepSeek Harness (DSH)' "${SKILLS}/using-superpowers/SKILL.md")"
check_eq "second install does not duplicate the bootstrap block" "1" \
  "$(grep -cF 'BEGIN superpowers-dsh bootstrap' "${DSHHOME}/AGENTS.md")"

# A third run after deleting one skill restores it.
rm -rf "${SKILLS}/writing-plans"
"$INSTALL" --target "$SKILLS" --dsh-home "$DSHHOME" >/dev/null 2>&1
check "restores a deleted skill" test -f "${SKILLS}/writing-plans/SKILL.md"

# ---------------------------------------------------------------------------
section "4. Bootstrap block"

AGENTS_MD="${DSHHOME}/AGENTS.md"
check "writes the bootstrap to \$DSH_HOME/AGENTS.md" test -f "$AGENTS_MD"
check "block is delimited by markers" \
  bash -c "grep -qF 'BEGIN superpowers-dsh bootstrap' '$AGENTS_MD' && grep -qF 'END superpowers-dsh bootstrap' '$AGENTS_MD'"
check "contains Superpowers' activation preamble" grep -qF 'You have superpowers.' "$AGENTS_MD"
check "contains the full using-superpowers body" grep -qF 'Red Flags' "$AGENTS_MD"
check "points at DSH's skill tool, not a Skill tool" \
  bash -c "grep -qF \"DSH's \\\`skill\\\` tool\" '$AGENTS_MD' && ! grep -qF \"use the 'Skill' tool\" '$AGENTS_MD'"

# Markers must be well-ordered and the block last.
check "BEGIN precedes END" \
  bash -c "[ \"\$(grep -nF 'BEGIN superpowers-dsh bootstrap' '$AGENTS_MD' | cut -d: -f1)\" -lt \"\$(grep -nF 'END superpowers-dsh bootstrap' '$AGENTS_MD' | cut -d: -f1)\" ]"

# Foreign content in AGENTS.md must survive a reinstall.
printf '# My own global instructions\n\nAlways use tabs.\n' | cat - "$AGENTS_MD" > "${AGENTS_MD}.tmp" && mv "${AGENTS_MD}.tmp" "$AGENTS_MD"
"$INSTALL" --target "$SKILLS" --dsh-home "$DSHHOME" >/dev/null 2>&1
check "preserves user content that precedes the block" \
  grep -qF 'Always use tabs.' "$AGENTS_MD"
check_eq "still exactly one block after reinstall over user content" "1" \
  "$(grep -cF 'BEGIN superpowers-dsh bootstrap' "$AGENTS_MD")"
check "user content stays above the block" \
  bash -c "[ \"\$(grep -nF 'Always use tabs.' '$AGENTS_MD' | cut -d: -f1)\" -lt \"\$(grep -nF 'BEGIN superpowers-dsh bootstrap' '$AGENTS_MD' | cut -d: -f1)\" ]"

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
  bash -c "! grep -qF 'superpowers-dsh bootstrap' '${H6}/AGENTS.md'"
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
  "$(grep -cF 'BEGIN superpowers-dsh bootstrap' "${H7}/AGENTS.md")"
check_eq "contains exactly one copy of the skill body" "1" \
  "$(grep -cF 'You have superpowers.' "${H7}/AGENTS.md")"
check_eq "contains exactly one closing tag" "1" \
  "$(grep -cF '</EXTREMELY_IMPORTANT>' "${H7}/AGENTS.md")"
check "user content survives above the block" \
  bash -c "[ \"\$(grep -nF 'Use tabs.' '${H7}/AGENTS.md' | cut -d: -f1)\" -lt \"\$(grep -nF 'BEGIN superpowers-dsh bootstrap' '${H7}/AGENTS.md' | cut -d: -f1)\" ]"

# A file that merely mentions the phrase further down must not be touched.
read -r S8 H8 <<<"$(fresh_prefix notlegacy)"
mkdir -p "$H8"
printf '# Notes\n\nI once read about a superpowers bootstrap for DSH.\n\nKeep me.\n' > "${H8}/AGENTS.md"
"$INSTALL" --target "$S8" --dsh-home "$H8" >/dev/null 2>&1
check "leaves a non-leading mention of the phrase alone" \
  grep -qF 'I once read about a superpowers bootstrap' "${H8}/AGENTS.md"
check "still appends the managed block below user notes" \
  grep -qF 'BEGIN superpowers-dsh bootstrap' "${H8}/AGENTS.md"

# ---------------------------------------------------------------------------
section "8. Bootstrap generator"

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
section "9. Patch script robustness"

check "patch script fails on a missing skill dir" \
  bash -c "! node '${REPO_ROOT}/lib/patch-using-superpowers.mjs' '${WORK}/nope' 2>/dev/null"
check "patch script fails on a restructured SKILL.md instead of silently skipping" \
  bash -c "d='${WORK}/restructured'; mkdir -p \"\$d\"; printf -- '---\nname: using-superpowers\ndescription: x\n---\n\nNo platform list here.\n' > \"\$d/SKILL.md\"; ! node '${REPO_ROOT}/lib/patch-using-superpowers.mjs' \"\$d\" 2>/dev/null"

# ---------------------------------------------------------------------------
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
