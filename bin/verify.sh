#!/usr/bin/env bash
# Verify a Superpowers-for-DSH installation against the LIVE DSH skill catalog.
#
# Most ports assert compatibility in prose. This resolves the catalog the same
# way the running harness does — by mounting DSH's own skill registry and
# filesystem provider in a bare Cordis context (see lib/dsh-resolve-skills.mjs)
# — and then checks the answers. It does not need DSH to be running, and it
# never writes anything.
#
# Usage: bin/verify.sh [options]
#
#   --target <dir>     Skill root to expect skills from
#                      (default: $DSH_AGENTS_HOME/skills or ~/.agents/skills)
#   --dsh-home <dir>   DSH home holding AGENTS.md (default: $DSH_HOME or ~/.dsh)
#   --modules <dir>    node_modules directory holding @deepseek-ai/dsh*
#                      (default: $DSH_NODE_MODULES, else auto-detected)
#   --json             Machine-readable output
#   -h, --help         This help
#
# Exit status: 0 all checks passed (warnings allowed), 1 a check failed,
# 2 usage or environment problem.
# ---
set -euo pipefail

# Resolve this script's real path before deriving REPO_ROOT. Run through npm's
# .bin symlink, a plain `dirname $0` resolves to <prefix>/.bin and REPO_ROOT
# would lose vendor/ and references/. readlink -f is not portable to macOS, so
# walk the symlink chain by hand.
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
readonly BOOTSTRAP_BEGIN="<!-- BEGIN dsh-superpowers-verified bootstrap -->"
readonly BOOTSTRAP_END="<!-- END dsh-superpowers-verified bootstrap -->"
readonly BOOTSTRAP_LEGACY_BEGIN="<!-- BEGIN superpowers-dsh bootstrap -->"
readonly BOOTSTRAP_LEGACY_END="<!-- END superpowers-dsh bootstrap -->"

target_skills=""
dsh_home=""
modules=""
json_out=0

die() { printf 'verify: %s\n' "$1" >&2; exit 2; }

usage() {
  awk 'NR > 1 && /^# ---/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)   [ "$#" -ge 2 ] || die "--target needs a value"; target_skills="$2"; shift 2 ;;
    --dsh-home) [ "$#" -ge 2 ] || die "--dsh-home needs a value"; dsh_home="$2"; shift 2 ;;
    --modules)  [ "$#" -ge 2 ] || die "--modules needs a value"; modules="$2"; shift 2 ;;
    --json)     json_out=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "unknown option: $1 (try --help)" ;;
  esac
done

[ -z "$target_skills" ] && target_skills="${DSH_AGENTS_HOME:-$HOME/.agents}/skills"
[ -z "$dsh_home" ] && dsh_home="${DSH_HOME:-$HOME/.dsh}"
agents_md="${dsh_home}/AGENTS.md"

# --- locate the DSH packages -------------------------------------------------

find_modules() {
  local candidate
  if [ -n "$modules" ]; then
    printf '%s\n' "$modules"
    return 0
  fi
  if [ -n "${DSH_NODE_MODULES:-}" ]; then
    printf '%s\n' "$DSH_NODE_MODULES"
    return 0
  fi
  # A global install of the launcher.
  candidate="$(npm root -g 2>/dev/null || true)"
  if [ -n "$candidate" ] && [ -d "${candidate}/@deepseek-ai/dsh-skill" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  # The npx cache, newest first: `npx @deepseek-ai/dsh` installs here.
  for candidate in $(ls -dt "${HOME}"/.npm/_npx/*/node_modules 2>/dev/null || true); do
    if [ -d "${candidate}/@deepseek-ai/dsh-skill" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

modules="$(find_modules || true)"
if [ -z "$modules" ]; then
  die "cannot find the DSH packages. Set DSH_NODE_MODULES to the node_modules directory that holds @deepseek-ai/dsh-skill, or pass --modules <dir>."
fi
[ -d "${modules}/@deepseek-ai/dsh-skill" ] || die "${modules} does not contain @deepseek-ai/dsh-skill"

# --- resolve the live catalog ------------------------------------------------

resolved="$(mktemp)"
trap 'rm -f "$resolved"' EXIT

if ! node "${REPO_ROOT}/lib/dsh-resolve-skills.mjs" "$modules" "$PWD" "$target_skills" > "$resolved" 2>"${resolved}.err"; then
  printf 'verify: failed to resolve the DSH skill catalog:\n' >&2
  sed 's/^/  /' "${resolved}.err" >&2 || true
  rm -f "${resolved}.err"
  exit 1
fi
rm -f "${resolved}.err"

# --- checks ------------------------------------------------------------------

pass=0; warn=0; fail=0
declare -a results

record() { # record <ok|warn|fail> <name> <detail>
  case "$1" in
    ok)   pass=$((pass + 1)) ;;
    warn) warn=$((warn + 1)) ;;
    fail) fail=$((fail + 1)) ;;
  esac
  results+=("$1|$2|$3")
}

json_get() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {'d': d}))" "$resolved" "$1"; }

# Resolve the winning source root for one skill name. The name is passed via the
# environment, never interpolated into the Python source.
skill_source() {
  local name="$1"
  SKILL_NAME="$name" python3 -c "
import json, os, sys
d = json.load(open(sys.argv[1]))
print(next((s['source'] for s in d['skills'] if s['name'] == os.environ['SKILL_NAME']), 'none'))
" "$resolved"
}

# 1. The catalog resolved completely. A partial read means the harness hit an
#    error mid-collection, so every later conclusion would be unsound.
if [ "$(json_get "d['complete']")" = "True" ]; then
  record ok "catalog resolves completely" "$(json_get "len(d['skills'])") skills"
else
  record fail "catalog resolves completely" "snapshot reported complete=false"
fi

# 2. Every skill this fork ships must be present in the live catalog. The
#    expected set comes from vendor/, not from the target directory: the target
#    is a shared root that may hold unrelated skills, and "every file in there
#    resolves" would not notice one of OUR skills failing to load.
readonly VENDOR_SKILLS="${REPO_ROOT}/vendor/superpowers/skills"
expected_names=()
if [ -d "$VENDOR_SKILLS" ]; then
  while IFS= read -r name; do expected_names+=("$name"); done < <(
    for d in "$VENDOR_SKILLS"/*/; do
      [ -f "${d}SKILL.md" ] && basename "$d"
    done | sort
  )
fi
if [ "${#expected_names[@]}" -eq 0 ]; then
  record warn "every vendored skill resolves" "no skills found in ${VENDOR_SKILLS}"
else
  # Present in the catalog is not enough: it must resolve FROM the root we are
  # auditing. A copy in a higher-precedence root would win and mask a broken
  # install, which is exactly the failure this tool exists to catch.
  missing="$(TARGET_DIR="$target_skills" python3 - "$resolved" "${expected_names[@]}" <<'PY'
import json, os, sys
snap = json.load(open(sys.argv[1]))
# realpath on both sides: on macOS /var is a symlink to /private/var, and
# the provider resolves the configured root, so abspath is not comparable.
target = os.path.realpath(os.environ["TARGET_DIR"])
found = {s["name"]: (s.get("path") or "") for s in snap["skills"]}
bad = [
    n for n in sys.argv[2:]
    if not found.get(n)
    or os.path.realpath(os.path.dirname(found[n])) != os.path.realpath(os.path.join(target, n))
]
print(" ".join(bad))
PY
)"
  if [ -z "$missing" ]; then
    record ok "every vendored skill resolves from --target" "${#expected_names[@]}/${#expected_names[@]} at ${target_skills}"
  else
    record fail "every vendored skill resolves from --target" "not resolving from ${target_skills}: ${missing}"
  fi
fi

# 3. The catalog's own validator rejects a colon outright, so a namespaced name
#    can never resolve. Note DSH *skips* such a file with a warning rather than
#    failing, so it never appears here — check 3b catches those on disk.
bad_names="$(json_get "' '.join(s['name'] for s in d['skills'] if ':' in s['name'])")"
if [ -z "$bad_names" ]; then
  record ok "no resolved skill name uses a namespace" "DSH requires /^[a-z0-9]+(-[a-z0-9]+)*$/"
else
  record fail "no resolved skill name uses a namespace" "unloadable: ${bad_names}"
fi

# 3b. A SKILL.md whose frontmatter name is not a legal DSH name is silently
#     skipped by the provider: installed but unreachable, and invisible in the
#     catalog. That is precisely why it has to be checked on disk.
rejected=""
if [ -d "$target_skills" ]; then
  for d in "$target_skills"/*/; do
    md="${d}SKILL.md"
    [ -f "$md" ] || continue
    fm="$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); gsub(/"/, ""); print; exit}' "$md")"
    case "$fm" in
      ""|*[!a-z0-9-]*|-*|*--*) rejected="${rejected} $(basename "$d")(name=${fm:-none})" ;;
    esac
  done
fi
if [ -z "$rejected" ]; then
  record ok "every installed skill has a loadable name" "checked every SKILL.md on disk"
else
  record fail "every installed skill has a loadable name" "DSH will skip these:${rejected}"
fi

# 4. Where do our skills come from? A copy in a higher-precedence root silently
#    shadows the installed one, which looks like "my edit did nothing". The
#    user-global DSH root (rank 400) outranks the agents root (rank 500).
lower_dsh="${dsh_home}/skills"
shadowed=""
sources=""
for name in "${expected_names[@]:-}"; do
  [ -n "$name" ] || continue
  src="$(skill_source "$name")"
  case " ${sources} " in *" ${src} "*) ;; *) sources="${sources} ${src}" ;; esac
  if [ -f "${lower_dsh}/${name}/SKILL.md" ]; then
    shadowed="${shadowed} ${name}"
  fi
done
if [ -z "$shadowed" ]; then
  record ok "no skill is shadowed by \$DSH_HOME/skills" "resolved from:${sources}"
else
  record warn "no skill is shadowed by \$DSH_HOME/skills" "also present in ${lower_dsh}:${shadowed}"
fi

# 5. The DSH reference file must be installed and advertised, because upstream's
#    skills cross-reference each other with a namespace DSH cannot load, and
#    that file is the only place the workaround is written down.
skill_dir="${target_skills}/using-superpowers"
if [ -f "${skill_dir}/references/dsh-tools.md" ]; then
  record ok "DSH reference file installed" "${skill_dir}/references/dsh-tools.md"
else
  record fail "DSH reference file installed" "missing ${skill_dir}/references/dsh-tools.md"
fi

if [ -f "${skill_dir}/SKILL.md" ]; then
  if grep -qF -- '- DeepSeek Harness (DSH): `references/dsh-tools.md`' "${skill_dir}/SKILL.md"; then
    record ok "adaptation list names DSH" "using-superpowers points at the DSH reference"
  else
    record fail "adaptation list names DSH" "using-superpowers does not point at references/dsh-tools.md; if `npx skills update` overwrote it, run bin/install.sh to repair"
  fi
  others="$(grep -cE '^- (Claude Code|Codex|Pi|Antigravity|Hermes Agent|Muse):' "${skill_dir}/SKILL.md" || true)"
  if [ "$others" -eq 0 ]; then
    record ok "no other harness is advertised" "only DSH is listed"
  else
    record fail "no other harness is advertised" "${others} other harness bullets remain (the platform patch did not run)"
  fi
  if [ -f "${skill_dir}/references/dsh-tools.md" ]; then
    if grep -qF 'Skill names carry no namespace prefix' "${skill_dir}/references/dsh-tools.md"; then
      record ok "namespace workaround is documented" "agents are told to strip the prefix"
    else
      record warn "namespace workaround is documented" "the reference file no longer explains the prefix rule"
    fi
  fi
fi

# 6. The bootstrap must be present, and its markers must pair up. An unpaired
#    marker means the installer refused to touch the file and warned instead.
if [ ! -e "$agents_md" ]; then
  record fail "bootstrap present in AGENTS.md" "${agents_md} does not exist (run bin/install.sh)"
else
  opens="$(grep -cF "$BOOTSTRAP_BEGIN" "$agents_md" || true)"
  closes="$(grep -cF "$BOOTSTRAP_END" "$agents_md" || true)"
  legacy_opens="$(grep -cF "$BOOTSTRAP_LEGACY_BEGIN" "$agents_md" || true)"
  if [ "$opens" -ge 1 ] && [ "$opens" -eq "$closes" ]; then
    if grep -qF 'You have superpowers.' "$agents_md"; then
      record ok "bootstrap present in AGENTS.md" "one balanced block in ${agents_md}"
    else
      record fail "bootstrap present in AGENTS.md" "block found but it carries no skill body"
    fi
  elif [ "$legacy_opens" -ge 1 ]; then
    record fail "bootstrap present in AGENTS.md" "pre-rename marker still in place; re-run bin/install.sh"
  elif [ "$opens" -gt 0 ] || [ "$closes" -gt 0 ]; then
    record fail "bootstrap present in AGENTS.md" "unpaired marker (${opens} BEGIN / ${closes} END); installer left the file untouched"
  else
    record fail "bootstrap present in AGENTS.md" "no managed block (run bin/install.sh)"
  fi
fi

# 7. Count the namespace references we know we do not patch. Informational: a
#    warning, not a failure, because the upstream bodies are unmodified by
#    design and the workaround is documented above.
ns_refs=0
if [ -d "$target_skills" ]; then
  ns_refs="$(grep -rhoE 'superpowers:[a-z][a-z0-9-]*' "$target_skills" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')"
fi
if [ "$ns_refs" -gt 0 ]; then
  record warn "upstream namespace references" "${ns_refs} references use superpowers:<name>; agents must strip the prefix"
else
  record ok "upstream namespace references" "none found"
fi

# --- report ------------------------------------------------------------------

if [ "$json_out" -eq 1 ]; then
  python3 - "${results[@]}" <<'PY'
import json, sys
checks = []
for entry in sys.argv[1:]:
    status, name, detail = entry.split("|", 2)
    checks.append({"status": status, "name": name, "detail": detail})
summary = {
    "passed": sum(c["status"] == "ok" for c in checks),
    "warnings": sum(c["status"] == "warn" for c in checks),
    "failed": sum(c["status"] == "fail" for c in checks),
}
json.dump({"checks": checks, "summary": summary}, sys.stdout, indent=2)
print()
PY
else
  printf 'Verifying Superpowers for DSH\n'
  printf '  modules: %s\n' "$modules"
  printf '  skills:  %s\n' "$target_skills"
  printf '  AGENTS:  %s\n\n' "$agents_md"
  for entry in "${results[@]}"; do
    status="${entry%%|*}"; rest="${entry#*|}"; name="${rest%%|*}"; detail="${rest#*|}"
    case "$status" in
      ok)   printf '  \033[32m✓\033[0m %-34s %s\n' "$name" "$detail" ;;
      warn) printf '  \033[33m!\033[0m %-34s %s\n' "$name" "$detail" ;;
      fail) printf '  \033[31m✗\033[0m %-34s %s\n' "$name" "$detail" ;;
    esac
  done
  printf '\n%d passed, %d warnings, %d failed\n' "$pass" "$warn" "$fail"
fi

[ "$fail" -eq 0 ] || exit 1
