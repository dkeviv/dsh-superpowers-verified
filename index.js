/**
 * dsh-superpowers-verified - DSH Plugin
 * 
 * Registers the 15 Superpowers skills and the session bootstrap for DSH.
 * This plugin provides the Superpowers methodology (brainstorming, planning,
 * TDD, systematic debugging, subagent-driven development) adapted for DSH.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILLS_DIR = join(__dirname, 'vendor', 'superpowers', 'skills');

/**
 * Load all skill definitions from the vendor directory
 */
function loadSkills() {
  const skills = {};
  const skillDirs = readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  for (const skillName of skillDirs) {
    const skillPath = join(SKILLS_DIR, skillName, 'SKILL.md');
    try {
      const content = readFileSync(skillPath, 'utf8');
      skills[skillName] = content;
    } catch (e) {
      console.warn(`Failed to load skill ${skillName}:`, e.message);
    }
  }
  return skills;
}

/**
 * Generate the bootstrap block for AGENTS.md / system prompt
 */
function generateBootstrap() {
  const skills = loadSkills();
  const usingSuperpowers = skills['using-superpowers'] || '';
  
  // Extract the skill content without frontmatter
  const content = using_superpowers.replace(/^---[\s\S]*?---\n/, '');
  
  return `<EXTREMELY_IMPORTANT>
You have superpowers.

**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use DSH's \`skill\` tool by name; the catalog is in your session context:**

---
${using_superpowers.replace(/^---[\s\S]*?---\n/, '').trim()}
</EXTREMELY_IMPORTANT>`;
}

/**
 * Main plugin entry point
 * Registers skills and bootstrap with DSH
 */
export function apply(ctx) {
  // Register all 15 Superpowers skills
  const skills = loadSkills();
  for (const [name, content] of Object.entries(skills)) {
    ctx.skills.register(name, content);
  }

  // Register the bootstrap as a system prompt section
  // This makes the Superpowers methodology active from the first turn
  const bootstrap = generateBootstrap();
  ctx.systemPrompt.section({
    name: 'superpowers:bootstrap',
    order: 10, // Early in the prompt, after persona
    text: generateBootstrap(),
  });

  // Also register the reference file for DSH tool mapping
  // The patch-using-superpowers.mjs installs references/dsh-tools.md into the skill
  // but we also make it available globally
  ctx.systemPrompt.section({
    name: 'superpowers:dsh-tools',
    order: 20,
    text: `# DSH Tool Reference

This file maps Superpowers skill instructions to DSH's actual tools.

| Superpowers Tool | DSH Equivalent |
|------------------|----------------|
| \`skill\` | \`skill\` (load skill by name) |
| \`Task\` | \`subagent\` / \`subagent_fork\` |
| \`TodoWrite\` / \`TodoRead\` | \`todo_write\` / \`todo_read\` |
| \`Bash\` | \`bash\` |
| \`Read\` / \`Write\` / \`Edit\` | \`read\` / \`write\` / \`edit\` |
| \`Grep\` / \`Glob\` | \`grep\` / \`glob\` |
| \`TodoWrite\` | \`todo_write\` |

DSH provides native plan mode, subagents, and file sandbox.
The \`skill\` tool loads skills by name from the catalog.
No \`Task\` / \`TodoWrite\` / \`Skill\` tools exist in DSH.
`
  });
}

export default { apply };
