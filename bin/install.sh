#!/usr/bin/env bash
# Install Superpowers for the DeepSeek Harness (DSH).
#
# Two independent things happen, and either can be skipped:
#
#   1. Skills   - copy the vendored Superpowers skills into DSH's global skill
#                 root ($DSH_AGENTS_HOME/skills, default ~/.agents/skills) and
#                 register DSH in `using-superpowers`'s platform-adaptation list.
#   2. Bootstrap- write Superpowers' session-start context into DSH's
#                 user-global instruction file ($DSH_HOME/AGENTS.md) so skills
#                 are active from the first turn of every session.
#
# Both steps are idempotent: re-running replaces what this installer owns and
# leaves everything else in the target files alone.
#
# Usage: bin/install.sh [options]
#
#   --target <dir>     Global skill root (default: $DSH_AGENTS_HOME/skills or
#                      ~/.agents/skills)
#   --dsh-home <dir>   DSH home holding AGENTS.md (default: $DSH_HOME or ~/.dsh)
#   --no-skills        Skip installing skills
#   --no-bootstrap     Skip writing the AGENTS.md bootstrap block
#   --dry-run          Print what would change; write nothing
#   -h, --help         This help
#
# Uninstall: bin/install.sh --uninstall [same options]
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly VENDOR_SKILLS="${REPO_ROOT}/vendor/superpowers/skills"
readonly BOOTSTRAP_BEGIN="<!-- BEGIN dsh-superpowers-verified bootstrap -->"
readonly BOOTSTRAP_END="<!-- END dsh-superpowers-verified bootstrap -->"
# This project shipped under the name `superpowers-dsh` before it was renamed.
# Installs made then carry the old markers in a live AGENTS.md, so they are
# still recognized and replaced rather than duplicated.
readonly BOOTSTRAP_LEGACY_BEGIN="<!-- BEGIN superpowers-dsh bootstrap -->"
readonly BOOTSTRAP_LEGACY_END="<!-- END superpowers-dsh bootstrap -->"

target_skills=""
dsh_home=""
do_skills=1
do_bootstrap=1
dry_run=0
uninstall=0

die() { printf 'install: %s\n' "$1" >&2; exit 1; }
note() { printf '%s\n' "$1"; }

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)        [ "$#" -ge 2 ] || die "--target needs a value"; target_skills="$2"; shift 2 ;;
    --dsh-home)      [ "$#" -ge 2 ] || die "--dsh-home needs a value"; dsh_home="$2"; shift 2 ;;
    --no-skills)     do_skills=0; shift ;;
    --no-bootstrap)  do_bootstrap=0; shift ;;
    --dry-run)       dry_run=1; shift ;;
    --uninstall)     uninstall=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown option: $1 (try --help)" ;;
  esac
done

# --- resolve locations -------------------------------------------------------

if [ -z "$target_skills" ]; then
  agents_home="${DSH_AGENTS_HOME:-$HOME/.agents}"
  target_skills="${agents_home}/skills"
fi
if [ -z "$dsh_home" ]; then
  dsh_home="${DSH_HOME:-$HOME/.dsh}"
fi
agents_md="${dsh_home}/AGENTS.md"

[ -d "$VENDOR_SKILLS" ] || die "vendored skills missing at ${VENDOR_SKILLS}"

# --- skill installation ------------------------------------------------------

install_skills() {
  local count=0 skill name
  for skill in "$VENDOR_SKILLS"/*/; do
    [ -d "$skill" ] || continue
    name="$(basename "$skill")"
    [ -f "${skill}SKILL.md" ] || die "vendored skill ${name} has no SKILL.md"

    if [ "$dry_run" -eq 1 ]; then
      note "would install skill ${name} -> ${target_skills}/${name}"
    else
      mkdir -p "${target_skills}/${name}"
      # -R preserves the executable bit on the skills' helper scripts.
      cp -R "${skill}." "${target_skills}/${name}/"
    fi
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || die "no vendored skills found in ${VENDOR_SKILLS}"

  if [ "$dry_run" -eq 1 ]; then
    note "would register DSH in ${target_skills}/using-superpowers/SKILL.md"
  else
    node "${REPO_ROOT}/lib/patch-using-superpowers.mjs" \
      "${target_skills}/using-superpowers" || die "failed to patch using-superpowers"
  fi
  note "skills: ${count} installed into ${target_skills}"
}

uninstall_skills() {
  local removed=0 name
  for name in $(cd "$VENDOR_SKILLS" && printf '%s\n' */ | sed 's#/$##'); do
    if [ -d "${target_skills}/${name}" ]; then
      if [ "$dry_run" -eq 1 ]; then
        note "would remove skill ${target_skills}/${name}"
      else
        rm -rf "${target_skills:?}/${name}"
      fi
      removed=$((removed + 1))
    fi
  done
  note "skills: ${removed} removed from ${target_skills}"
}

# --- bootstrap ---------------------------------------------------------------

# Replace our marked block in $1, or append it if absent. Content on stdin.
write_bootstrap_block() {
  local file="$1" block_file="$2" tmp
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp "${file}.XXXXXX")"

  if [ -f "$file" ]; then
    # Drop any previous block (and the blank line we add before it), keeping
    # everything the user wrote. Both the current and the pre-rename markers
    # are stripped, so a `superpowers-dsh` install upgrades cleanly in place.
    awk -v b="$BOOTSTRAP_BEGIN" -v e="$BOOTSTRAP_END" \
        -v b2="$BOOTSTRAP_LEGACY_BEGIN" -v e2="$BOOTSTRAP_LEGACY_END" '
      index($0, b) || index($0, b2) { skip = 1; next }
      index($0, e) || index($0, e2) { skip = 0; next }
      !skip { print }
    ' "$file" > "$tmp"
  fi

  # Trim trailing blank lines so repeated installs do not accumulate them.
  if [ -s "$tmp" ]; then
    awk 'BEGIN{n=0} {lines[NR]=$0} END{last=NR; while(last>0 && lines[last] ~ /^[[:space:]]*$/) last--; for(i=1;i<=last;i++) print lines[i]}' "$tmp" > "${tmp}.trim"
    mv "${tmp}.trim" "$tmp"
    printf '\n' >> "$tmp"
  fi

  cat "$block_file" >> "$tmp"

  # Drop a legacy block that predates the self-managed markers. Without this,
  # migrating from a manually-installed bootstrap duplicates the entire skill
  # body into the instruction file, which then ships to every session.
  strip_legacy_bootstrap "$tmp"

  mv "$tmp" "$file"
}

# Remove a pre-markers Superpowers bootstrap block, if the file opens with one.
#
# Early/ad-hoc installs (including the block this project's own docs used before
# markers existed) wrote the block at the top of AGENTS.md, introduced by a
# comment naming the manual uninstall route. Only a leading block is stripped:
# a user's own content is never reachable by this rule, and a file that merely
# mentions the phrase further down is left alone.
strip_legacy_bootstrap() {
  local file="$1"
  [ -s "$file" ] || return 0
  head -n 1 "$file" | grep -qF 'superpowers bootstrap' || return 0
  grep -qF 'To remove Superpowers' "$file" || return 0

  awk '
    NR == 1 { if ($0 !~ /superpowers bootstrap/) { print; next } else { inblock = 1; next } }
    inblock {
      if (index($0, "</EXTREMELY_IMPORTANT>") > 0) { inblock = 0; dropgap = 1 }
      next
    }
    dropgap { if ($0 ~ /^[[:space:]]*$/) next; dropgap = 0 }
    { print }
  ' "$file" > "${file}.stripped"
  mv "${file}.stripped" "$file"
  note "bootstrap: removed a legacy pre-markers block from ${agents_md}"
}

install_bootstrap() {
  local skill_dir="${target_skills}/using-superpowers"
  local block_file

  if [ ! -r "${skill_dir}/SKILL.md" ]; then
    die "cannot build bootstrap: ${skill_dir}/SKILL.md not found (install skills first)"
  fi

  block_file="$(mktemp)"
  {
    printf '%s\n' "$BOOTSTRAP_BEGIN"
    printf '<!-- Managed by dsh-superpowers-verified. Regenerated by bin/install.sh; edits here are overwritten. -->\n'
    printf '<!-- Make Superpowers active from the first turn of every DSH session. -->\n'
    printf '<!-- Remove with: bin/install.sh --uninstall -->\n'
    bash "${REPO_ROOT}/lib/session-start.sh" "$skill_dir"
    printf '%s\n' "$BOOTSTRAP_END"
  } > "$block_file"

  if [ "$dry_run" -eq 1 ]; then
    note "would write Superpowers bootstrap into ${agents_md} ($(wc -c < "$block_file" | tr -d ' ') bytes)"
    rm -f "$block_file"
    return 0
  fi

  write_bootstrap_block "$agents_md" "$block_file"
  rm -f "$block_file"
  note "bootstrap: wrote ${agents_md}"
}

uninstall_bootstrap() {
  if [ ! -f "$agents_md" ]; then
    note "bootstrap: ${agents_md} does not exist"
    return 0
  fi
  if ! grep -qF "$BOOTSTRAP_BEGIN" "$agents_md" && ! grep -qF "$BOOTSTRAP_LEGACY_BEGIN" "$agents_md"; then
    note "bootstrap: no self-managed block in ${agents_md}"
    return 0
  fi
  if [ "$dry_run" -eq 1 ]; then
    note "would remove the bootstrap block from ${agents_md}"
    return 0
  fi
  local tmp
  tmp="$(mktemp "${agents_md}.XXXXXX")"
  awk -v b="$BOOTSTRAP_BEGIN" -v e="$BOOTSTRAP_END" \
      -v b2="$BOOTSTRAP_LEGACY_BEGIN" -v e2="$BOOTSTRAP_LEGACY_END" '
    index($0, b) || index($0, b2) { skip = 1; next }
    index($0, e) || index($0, e2) { skip = 0; next }
    !skip { print }
  ' "$agents_md" > "$tmp"
  if [ -s "$tmp" ]; then mv "$tmp" "$agents_md"; else rm -f "$tmp" "$agents_md"; fi
  note "bootstrap: removed the block from ${agents_md}"
}

# --- run ---------------------------------------------------------------------

if [ "$uninstall" -eq 1 ]; then
  [ "$dry_run" -eq 1 ] && note "--- dry run ---"
  [ "$do_bootstrap" -eq 1 ] && uninstall_bootstrap
  [ "$do_skills" -eq 1 ] && uninstall_skills
  note "done. Restart any running DSH session to pick up the change."
  exit 0
fi

[ "$dry_run" -eq 1 ] && note "--- dry run: nothing will be written ---"
[ "$do_skills" -eq 1 ] && install_skills
if [ "$do_bootstrap" -eq 1 ]; then
  install_bootstrap
fi
note "done. Skills are live immediately; restart any running DSH session so the bootstrap is loaded."
