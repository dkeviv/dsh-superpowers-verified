/**
 * Patch the installed `using-superpowers` skill so Superpowers' own
 * platform-adaptation mechanism points at DSH.
 *
 * Upstream keeps a "Platform Adaptation" list in `using-superpowers/SKILL.md`
 * naming one reference file per supported harness. Registering DSH means adding
 * a single `- DeepSeek Harness (DSH): ...` bullet and copying our reference
 * file into that skill's `references/` directory. Nothing else upstream is
 * modified, so the skill keeps working if DSH support is later removed and the
 * diff against upstream stays reviewable.
 *
 * Usage: node lib/patch-using-superpowers.mjs <installed-skill-dir>
 */
import { readFileSync, writeFileSync, copyFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const SKILL_FILE = "SKILL.md";
const REFERENCE_SOURCE = "dsh-tools.md";
const REFERENCE_TARGET = "references/dsh-tools.md";
const BULLET = "- DeepSeek Harness (DSH): `references/dsh-tools.md`";
const ANCHOR = "- Muse: `references/muse-tools.md`";

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

// Idempotent: a second install must not append a duplicate bullet.
if (text.includes(BULLET)) {
  console.log("patch: platform-adaptation bullet already present");
  process.exit(0);
}

if (!text.includes(ANCHOR)) {
  // Upstream restructured the list. Fail loudly rather than silently shipping a
  // skill that never mentions DSH: without the bullet, an agent on DSH has no
  // pointer to this file.
  console.error(
    `patch: anchor ${JSON.stringify(ANCHOR)} not found in ${skillPath}.\n` +
      "Upstream's Platform Adaptation list changed. Update ANCHOR in " +
      "lib/patch-using-superpowers.mjs, and keep references/dsh-tools.md in sync.",
  );
  process.exit(1);
}

writeFileSync(skillPath, text.replace(ANCHOR, `${ANCHOR}\n${BULLET}`));
console.log(`patch: registered DSH in ${skillPath}`);
console.log(`patch: installed ${REFERENCE_TARGET}`);
