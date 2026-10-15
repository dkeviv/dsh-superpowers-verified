#!/usr/bin/env node
/**
 * Resolve the DeepSeek Harness skill catalog WITHOUT booting DSH.
 *
 * DSH's own skill service is an ordinary Cordis service, and both the registry
 * and the filesystem provider export their plugin entry points, so they can be
 * mounted in a bare `Context`. That gives a standalone script the same answer
 * the running harness would compute — name, originating root, provider, and
 * absolute SKILL.md path for every skill that resolves.
 *
 * This is deliberately the only place that touches DSH internals, and its
 * inputs are documented so a DSH change fails here (see bin/verify.sh) rather
 * than silently reporting an empty or partial catalog.
 *
 * Usage: node lib/dsh-resolve-skills.mjs <dsh-node-modules-dir> [cwd] [extra-root]
 *
 * `extra-root` is added as a `custom` root (rank 300, above the user-global
 * roots) so a caller can audit a non-default install location.
 * Prints one JSON object on stdout.
 */
import { pathToFileURL } from "node:url";
import { join } from "node:path";
import { createRequire } from "node:module";

const [, , modulesDir, cwdArg, extraRootArg] = process.argv;
if (!modulesDir) {
  process.stderr.write("dsh-resolve-skills: needs the DSH node_modules directory\n");
  process.exit(2);
}

/**
 * Import a DSH package by NAME, resolved from the given node_modules tree.
 *
 * Resolving by specifier rather than by guessing a file path keeps this
 * working if a package rearranges its lib/ layout, and it fails with a clear
 * message if the package is absent.
 */
async function loadPackage(specifier, what) {
  const require = createRequire(join(modulesDir, "noop.js"));
  let entry;
  try {
    entry = require.resolve(specifier);
  } catch {
    throw new Error(
      `cannot resolve ${specifier} (${what}) from ${modulesDir}. ` +
        "Pass the node_modules directory that holds @deepseek-ai/dsh*.",
    );
  }
  try {
    return await import(pathToFileURL(entry).href);
  } catch (error) {
    throw new Error(`cannot import ${specifier} from ${entry}: ${error.message}`);
  }
}

const ctx = {
  dshHome: null,
  agentsHome: null,
  cwd: cwdArg ?? process.cwd(),
  extraRoot: extraRootArg ?? null,
  skills: [],
  complete: false,
};

try {
  const { Context } = await loadPackage("@deepseek-ai/cordis", "Cordis runtime");
  const registryModule = await loadPackage("@deepseek-ai/dsh-skill", "skill registry");
  const filesystemModule = await loadPackage(
    "@deepseek-ai/dsh-skill-filesystem",
    "filesystem skill provider",
  );
  const homePaths = await loadPackage("@deepseek-ai/dsh-home-paths", "DSH home paths");

  const SkillRegistry = registryModule.default ?? registryModule.SkillRegistry;
  if (typeof SkillRegistry !== "function") {
    throw new Error("dsh-skill no longer exports the SkillRegistry class");
  }

  const dshHome = homePaths.resolveDshHome(process.env.DSH_HOME);
  const agentsHome =
    process.env.DSH_AGENTS_HOME ?? join(homePaths.expandHomePath?.("~") ?? process.env.HOME, ".agents");

  const root = new Context();
  await root.plugin(SkillRegistry, {});

  // The provider must be mounted with its `inject` declaration intact. A bare
  // `apply` function loses it, and then the provider's own `ctx.skills` lookup
  // fails with "cannot get property skills without inject" — the provider
  // would mount but resolve nothing. Cordis reads the declaration off the
  // plugin object, so re-wrap it rather than passing `apply` directly.
  const providerPlugin = filesystemModule.apply
    ? { apply: filesystemModule.apply, inject: filesystemModule.inject ?? ["skills"] }
    : filesystemModule.default;
  if (!providerPlugin) {
    throw new Error("dsh-skill-filesystem no longer exports an `apply` entry point");
  }

  // watch:false is required — the provider's chokidar watchers otherwise keep
  // the event loop alive and this process never exits.
  await root.plugin(providerPlugin, {
    dshHome,
    agentsHome,
    includeDefaultRoots: true,
    customSkillDirs: extraRootArg ? [extraRootArg] : [],
    watch: false,
  });

  const snapshot = await root.skills.snapshot({ cwd: ctx.cwd });
  const skills = snapshot.skills ?? [];
  ctx.complete = snapshot.complete !== false;
  ctx.dshHome = dshHome;
  ctx.agentsHome = agentsHome;
  ctx.skills = skills.map((skill) => ({
    name: skill.name,
    description: skill.description,
    source: skill.source,
    provider: skill.provider,
    path: skill.path,
    resourceBase: skill.resourceBase?.path ?? null,
  }));

  // Deliberately not disposed: the provider registers a watcher only when
  // watch:true. Exiting here keeps the script single-shot and side-effect free.
  process.stdout.write(`${JSON.stringify(ctx, null, 2)}\n`);
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(3);
}
