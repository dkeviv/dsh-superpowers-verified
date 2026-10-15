/**
 * Patch the installed `using-superpowers` skill for the DeepSeek Harness.
 *
 * Upstream keeps a "Platform Adaptation" list in `using-superpowers/SKILL.md`
 * naming one reference file per harness upstream supports. On DSH most of that
 * list is a footgun — an agent can follow `claude-code-tools.md` and then reach
 * for `Task` or `TodoWrite`, which do not exist here. So this rewrites the list
 * to name DSH alone, installs our DSH reference file, and removes the reference
 * files for harnesses that are no longer named. Everything else upstream is
 * untouched, so the diff stays reviewable and DSH support can be dropped cleanly.
 *
 * Usage: node lib/patch-using-superpowers.mjs <installed-skill-dir>
 */
import {
  readFileSync,
  writeFileSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  rmSync,
} from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const SKILL_FILE = "SKILL.md";
const REFERENCE_SOURCE = "dsh-tools.md";
// Basename, for comparing against readdirSync() output.
const REFERENCE_NAME = "dsh-tools.md";
const REFERENCE_TARGET = `references/${REFERENCE_NAME}`;
// Kept because one upstream cross-reference names it; never advertised.
const KEEP_REFERENCE = "claude-code-tools.md";
const BULLET = `- DeepSeek Harness (DSH): \`${REFERENCE_TARGET}\``;

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const referenceSourcePath = join(repoRoot, "references", REFERENCE_SOURCE);

const skillDir = process.argv[2];
if (!skillDir) {
  console.error("usage: node lib/patch-using-superpowers.mjs <installed-skill-dir>");
  process.exit(2);
}

const skillPath = join(skillDir, SKILL_FILE);
if (!existsSync(skillPath)) {
  console.error(`patch: ${skillPath} not found`);
  process.exit(1);
}
if (!existsSync(referenceSourcePath)) {
  console.error(`patch: reference source ${referenceSourcePath} not found`);
  process.exit(1);
}

// Copy the reference file first: a bullet pointing at a missing file would be
// worse than no bullet at all.
const referenceTargetPath = join(skillDir, REFERENCE_TARGET);
mkdirSync(dirname(referenceTargetPath), { recursive: true });
copyFileSync(referenceSourcePath, referenceTargetPath);

const text = readFileSync(skillPath, "utf8");

// The upstream list names every harness upstream supports. On DSH that list is
// a footgun rather than a help: an agent reading it can pick
// `claude-code-tools.md` and then try to reach for `Task` / `TodoWrite`, which
// do not exist here. Replace the whole list with the DSH entry so DSH is the
// only platform advertised.
//
// Install is expected to be re-runnable, so a file already carrying our intro
// is left alone rather than treated as an unrecognized format.
const INTRO =
  "This build of Superpowers runs on the DeepSeek Harness (DSH). Read the DSH\n" +
  "reference file for how these skills map onto DSH's tools:\n\n";

const listPattern =
  /If your harness appears here, read its reference file for special instructions:\n\n(?:- .+\n)+/;

if (!text.includes(INTRO)) {
  if (!listPattern.test(text)) {
    // Upstream restructured the list and this is not our own output. Fail
    // loudly: silently installing a skill that never mentions DSH, or that
    // still points at Claude Code, is worse than a failed install.
    console.error(
      `patch: upstream's Platform Adaptation list was not found in ${skillPath}.\n` +
        "Update listPattern in lib/patch-using-superpowers.mjs, and keep " +
        "references/dsh-tools.md in sync with any new instructions upstream " +
        "added for other harnesses.",
    );
    process.exit(1);
  }
  writeFileSync(skillPath, text.replace(listPattern, INTRO + `${BULLET}\n`));
  console.log("patch: rewrote the platform-adaptation list for DSH");
} else {
  console.log("patch: platform-adaptation list already DSH-only");
}

// Drop the other harnesses' reference files. Nothing points at them any more,
// and at ~44 KB they are pure context bloat if an agent browses the directory.
// This runs every install so a re-install repairs a manually restored file.
const referenceDir = dirname(referenceTargetPath);
for (const other of readdirSync(referenceDir)) {
  if (!other.endsWith("-tools.md")) continue;
  if (other === REFERENCE_NAME || other === KEEP_REFERENCE) continue;
  rmSync(join(referenceDir, other));
}
console.log(`patch: registered DSH in ${skillPath}`);
console.log(`patch: installed ${REFERENCE_TARGET}`);
