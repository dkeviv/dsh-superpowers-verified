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
# The `skills` CLI is a second owner of the same skill root. `npx skills update`
# recopies upstream verbatim and strips this fork's DSH adaptation. Re-running
# this installer detects that and repairs it; --check reports it without
# writing, for use in a hook or a health check.
#
# Usage: bin/install.sh [options]
#
#   --target <dir>     Global skill root (default: $DSH_AGENTS_HOME/skills or
#                      ~/.agents/skills)
#   --dsh-home <dir>   DSH home holding AGENTS.md (default: $DSH_HOME or ~/.dsh)
#   --no-skills        Skip installing skills
#   --no-bootstrap     Skip writing the AGENTS.md bootstrap block
#   --dry-run          Print what would change; write nothing
#   --check            Report whether a repair is needed; write nothing
#   --uninstall        Remove the installed skills and the bootstrap block
#   -h, --help         This help
# ---
set -euo pipefail

# Resolve $1 to its real on-disk path, following a chain of symlinks.
#
# This matters when the script is run through a symlink: npm's .bin shim points
# at bin/install.sh, so `dirname $0` is <prefix>/.bin and REPO_ROOT would land
# on <prefix>/ instead of the package directory, losing vendor/ and
# references/. `readlink -f` is not portable to macOS, so walk the chain by hand.
resolve_self() {
  local path="$1" dir link hops=0
  while [ -L "$path" ] && [ "$hops" -lt 40 ]; do
    dir="$(cd -P "$(dirname "$path")" && pwd)"
    link="$(readlink "$path")"
    case "$link" in
      /*) path="$link" ;;
      *)  path="${dir}/${link}" ;;
    esac
    hops=$((hops + 1))
  done
  dir="$(cd -P "$(dirname "$path")" && pwd)"
  printf '%s\n' "${dir}/$(basename "$path")"
}

readonly SELF="$(resolve_self "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(dirname "$SELF")"
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
check_only=0

die() { printf 'install: %s\n' "$1" >&2; exit 1; }
warn() { printf 'install: warning: %s\n' "$1" >&2; }
note() { printf '%s\n' "$1"; }

# Print the header comment as help. Bounded by the header's own markers rather
# than hard-coded line numbers, so editing the comment cannot silently truncate
# or leak the script body into --help.
usage() {
  awk 'NR > 1 && /^# ---/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)        [ "$#" -ge 2 ] || die "--target needs a value"; target_skills="$2"; shift 2 ;;
    --dsh-home)      [ "$#" -ge 2 ] || die "--dsh-home needs a value"; dsh_home="$2"; shift 2 ;;
    --no-skills)     do_skills=0; shift ;;
    --no-bootstrap)  do_bootstrap=0; shift ;;
    --dry-run)       dry_run=1; shift ;;
    --uninstall)     uninstall=1; shift ;;
    --check)         check_only=1; shift ;;
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

# Is the installed `using-superpowers` missing our DSH adaptation?
#
# The `skills` CLI is a second, independent owner of the same skill root. When
# it updates Superpowers it recopies upstream's body verbatim, which silently
# removes the DSH platform list, deletes `references/dsh-tools.md`, and restores
# the other harnesses' reference files. The CLI has no hook we could use, so the
# repair has to be detectable and cheap: every installer run checks for this and
# reapplies the adaptation.
needs_repair() {
  local dir="${target_skills}/using-superpowers"
  [ -d "$dir" ] || return 1
  [ -f "${dir}/SKILL.md" ] || return 1
  # Upstream verbatim means our marker and reference file are both absent.
  [ ! -f "${dir}/references/dsh-tools.md" ] && return 0
  ! grep -qF -- '- DeepSeek Harness (DSH): `references/dsh-tools.md`' "${dir}/SKILL.md" && return 0
  return 1
}

install_skills() {
  local count=0 skill name
  if [ "$dry_run" -eq 1 ]; then
    needs_repair && warn "--target is missing the DSH adaptation (the skills CLI overwrote it); this run would repair it"
  elif needs_repair; then
    warn "the installed Superpowers lost its DSH adaptation (usually \`npx skills update\`); repairing"
  fi
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

# Resolve $1 to the path that should actually be written, following a symlink.
#
# The atomic `mv` below replaces a directory entry. If AGENTS.md is a symlink
# (a common dotfiles arrangement), writing to the link path would replace the
# link with a regular file and silently stop managing the user's real file.
#
# Only the FINAL component is resolved, via readlink. Canonicalising the parent
# with `cd -P` would also rewrite the directory itself (/var -> /private/var on
# macOS), landing the write next to the symlink instead of at its target.
resolve_write_target() {
  local file="$1" dir link hops=0
  while [ -L "$file" ] && [ "$hops" -lt 40 ]; do
    dir="$(dirname "$file")"
    link="$(readlink "$file")" || break
    case "$link" in
      /*) file="$link" ;;
      *)  file="${dir}/${link}" ;;
    esac
    hops=$((hops + 1))
  done
  printf '%s\n' "$file"
}

# Remove our managed blocks from stdin, printing the remainder.
#
# Both the current and the pre-rename markers are handled so an install from
# before the rename is replaced in place rather than duplicated.
#
# Markers are matched as WHOLE LINES, after stripping leading whitespace. A
# substring match is wrong here: the pre-rename block's own body contains the
# comment "Managed by superpowers-dsh ...", which contains today's marker text
# as a substring, so `index()` would treat that comment as a BEGIN and corrupt
# the block.
#
# Safety rule, in two passes:
#   1. Count BEGIN and END markers (whole lines). If they do not pair up, the
#      file has been hand-edited or truncated, and we cannot know where the
#      block ends. Reproduce the file byte-for-byte and let the caller decide,
#      rather than guessing and swallowing user content.
#   2. Only with paired markers, remove the blocks.
#
# The state machine is written with if/else rather than `pattern { next }`
# rules on purpose. On macOS's /usr/bin/awk (onetrueawk 20200816) a
# `skip { print; next }` rule following a `next` rule prints lines it was
# supposed to swallow, which silently left a replaced block's body in place.
# The if/else form is identical on that awk and on gawk/mawk.
strip_managed_blocks() {
  awk -v b="$BOOTSTRAP_BEGIN" -v e="$BOOTSTRAP_END" \
      -v b2="$BOOTSTRAP_LEGACY_BEGIN" -v e2="$BOOTSTRAP_LEGACY_END" '
    function trimmed(l) { sub(/^[ \t]+/, "", l); sub(/[ \t\r]+$/, "", l); return l }
    {
      raw[NR] = $0
      line = trimmed($0)
      if (line == b || line == b2) opens++
      else if (line == e || line == e2) closes++
    }
    END {
      if (opens != closes) {
        unbalanced = 1
        for (i = 1; i <= NR; i++) print raw[i]
        exit 0
      }
      for (i = 1; i <= NR; i++) {
        line = trimmed(raw[i])
        if (!skip && (line == b || line == b2)) skip = 1
        else if (skip && (line == e || line == e2)) skip = 0
        else if (!skip) print raw[i]
      }
    }
  '
}

# True when stdin holds a balanced pair of our managed markers.
has_balanced_block() {
  awk -v b="$BOOTSTRAP_BEGIN" -v e="$BOOTSTRAP_END" \
      -v b2="$BOOTSTRAP_LEGACY_BEGIN" -v e2="$BOOTSTRAP_LEGACY_END" '
    function trimmed(l) { sub(/^[ \t]+/, "", l); sub(/[ \t\r]+$/, "", l); return l }
    {
      line = trimmed($0)
      if (line == b || line == b2) opens++
      else if (line == e || line == e2) closes++
    }
    END { exit (opens > 0 && opens == closes) ? 0 : 1 }
  '
}

# Delete a trailing run of blank lines, then add exactly one separator newline
# if any user content remains. Callers use this to normalise the join between
# user content and our block, so repeated installs and uninstalls do not drift.
normalise_trailing_blanks() {
  awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print lines[i]
    }
  '
}

# Replace our marked block in $1, or append it if absent. Block content in $2.
write_bootstrap_block() {
  local file="$1" block_file="$2"
  local target tmp
  local had_block=0

  target="$(resolve_write_target "$file")"
  mkdir -p "$(dirname "$target")"

  # mktemp creates the staged file 0600; the final mode is set explicitly below
  # so a world-readable temp never becomes the user's instruction file.
  tmp="$(mktemp "${target}.XXXXXX")" || return 1

  if [ -f "$target" ]; then
    if has_balanced_block < "$target"; then
      # A complete block we can safely replace.
      had_block=1
    elif grep -qF "$BOOTSTRAP_BEGIN" "$target" || grep -qF "$BOOTSTRAP_LEGACY_BEGIN" "$target"; then
      # Markers present but not paired: hand-edited or truncated. We cannot
      # tell where the block ends, so leave the file exactly as-is and append
      # our block after it. Losing user content to a guess is far worse than
      # leaving a stale marker line in place.
      warn "bootstrap: ${target} has an unpaired marker; leaving its content untouched"
    fi
    # Strip our blocks, drop the trailing run of blank lines, then re-add
    # exactly one separator newline — but only when user content remains.
    # One pipeline, so there is no intermediate copy to get out of step with
    # the staged file.
    {
      strip_managed_blocks < "$target" | normalise_trailing_blanks
    } > "$tmp"
  fi

  if [ -s "$tmp" ]; then
    printf '\n' >> "$tmp"
  fi
  cat "$block_file" >> "$tmp"

  # Drop a legacy block that predates the self-managed markers. Without this,
  # migrating from a manually-installed bootstrap duplicates the entire skill
  # body into the instruction file, which then ships to every session.
  strip_legacy_bootstrap "$tmp"

  set_file_mode "$tmp" "$target"
  mv "$tmp" "$target" || { rm -f "$tmp"; return 1; }

  if [ "$had_block" -eq 1 ]; then
    note "bootstrap: replaced the existing block in ${target}"
  fi
  return 0
}

# Give $1 the mode of $2, or 0600 when $2 does not exist.
#
# Replacing a file via mv discards the original mode, which would silently make
# a 0600 AGENTS.md world-readable. Stat syntax differs between GNU and BSD, and
# the order matters: on GNU, `stat -f` means --file-system and SUCCEEDS while
# printing filesystem statistics, so a BSD-first fallback captures garbage and
# the caller falls through to a default. Try the GNU form first (it fails on
# BSD), then the BSD form, and validate the result before applying it.
set_file_mode() {
  local new="$1" existing="$2" mode=""
  if [ -e "$existing" ]; then
    mode="$(stat -c '%a' "$existing" 2>/dev/null | tr -d '[:space:]' || true)"
    if ! printf '%s' "$mode" | grep -qE '^[0-7]{3,4}$'; then
      mode="$(stat -f '%Lp' "$existing" 2>/dev/null | tr -d '[:space:]' || true)"
    fi
  fi
  if printf '%s' "$mode" | grep -qE '^[0-7]{3,4}$'; then
    chmod "$mode" "$new" 2>/dev/null || true
  else
    chmod 600 "$new" 2>/dev/null || true
  fi
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
  local target
  target="$(resolve_write_target "$agents_md")"
  if [ ! -f "$target" ]; then
    note "bootstrap: ${agents_md} does not exist"
    return 0
  fi
  if ! grep -qF "$BOOTSTRAP_BEGIN" "$target" && ! grep -qF "$BOOTSTRAP_LEGACY_BEGIN" "$target"; then
    note "bootstrap: no self-managed block in ${agents_md}"
    return 0
  fi
  if [ "$dry_run" -eq 1 ]; then
    note "would remove the bootstrap block from ${agents_md}"
    return 0
  fi

  local tmp body
  tmp="$(mktemp "${target}.XXXXXX")" || return 1
  body="$(mktemp "${target}.body.XXXXXX")" || { rm -f "$tmp"; return 1; }

  # Strip the block, then normalise the join so install/uninstall round-trips
  # are a true no-op instead of accumulating a blank line per cycle.
  strip_managed_blocks < "$target" > "$tmp"
  normalise_trailing_blanks < "$tmp" > "$body"

  if [ -s "$body" ]; then
    # Keep the user's content and its original permissions.
    cp "$body" "$tmp"
    set_file_mode "$tmp" "$target"
    mv "$tmp" "$target" || { rm -f "$tmp" "$body"; return 1; }
    note "bootstrap: removed the block from ${agents_md}"
  else
    # The block was the file's only content, leaving nothing behind. Remove the
    # file itself, but only after confirming there is genuinely no user content
    # — an orphaned BEGIN that we refuse to swallow would leave text here.
    chmod u+w "$target" 2>/dev/null || true
    rm -f "$target" || { rm -f "$tmp" "$body"; return 1; }
    note "bootstrap: removed ${agents_md} (it held nothing else)"
  fi
  rm -f "$tmp" "$body"
}

# --- run ---------------------------------------------------------------------

if [ "$check_only" -eq 1 ]; then
  if [ ! -d "${target_skills}/using-superpowers" ]; then
    note "not installed: ${target_skills}/using-superpowers does not exist"
    note "fix:   $0 --target ${target_skills}"
    exit 1
  fi
  if needs_repair; then
    note "needs repair: ${target_skills}/using-superpowers is missing the DSH adaptation"
    note "cause: something reinstalled upstream over it, typically \`npx skills update\`"
    note "fix:   $0 --target ${target_skills}"
    exit 1
  fi
  note "ok: the DSH adaptation is intact in ${target_skills}"
  exit 0
fi

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
