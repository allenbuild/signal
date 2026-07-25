import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const extensionRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputRoot = resolve(extensionRoot, "dist");

await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });

const common = {
  absWorkingDir: extensionRoot,
  bundle: true,
  legalComments: "none",
  logLevel: "info",
  minify: true,
  sourcemap: false,
  target: "chrome116",
  define: {
    "process.env.NODE_ENV": '"production"',
  },
};

await Promise.all([
  build({
    ...common,
    entryPoints: ["src/background/service-worker.ts"],
    format: "esm",
    outfile: "dist/background/service-worker.js",
  }),
  build({
    ...common,
    entryPoints: ["src/content/content-script.ts"],
    format: "iife",
    globalName: "SignalContentRuntime",
    outfile: "dist/content/content-script.js",
  }),
  build({
    ...common,
    entryPoints: ["src/offscreen/offscreen.ts"],
    format: "iife",
    globalName: "SignalOffscreenRuntime",
    outfile: "dist/offscreen/offscreen.js",
  }),
  build({
    ...common,
    entryPoints: ["src/sidepanel/main.tsx"],
    format: "iife",
    globalName: "SignalSidePanel",
    outfile: "dist/sidepanel/app.js",
  }),
  build({
    ...common,
    entryPoints: ["src/setup/setup.ts"],
    format: "iife",
    globalName: "SignalPermissionSetup",
    outfile: "dist/setup/setup.js",
  }),
]);

async function copyText(source, destination) {
  const target = resolve(outputRoot, destination);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, await readFile(resolve(extensionRoot, source), "utf8"));
}

await Promise.all([
  copyText("manifest.json", "manifest.json"),
  copyText("src/offscreen/offscreen.html", "offscreen/offscreen.html"),
  copyText("src/sidepanel/index.html", "sidepanel/index.html"),
  copyText("src/setup/setup.html", "setup/setup.html"),
  copyText("README.md", "README.md"),
  copyText("RELEASE_NOTES.md", "RELEASE_NOTES.md"),
  copyText("KNOWN_LIMITATIONS.md", "KNOWN_LIMITATIONS.md"),
  copyText("demo-profile.json", "demo-profile.json"),
  cp(resolve(extensionRoot, "public"), outputRoot, { recursive: true }),
]);

const manifest = JSON.parse(
  await readFile(resolve(outputRoot, "manifest.json"), "utf8"),
);
const serialized = JSON.stringify(manifest);
for (const forbidden of [
  "nativeMessaging",
  "debugger",
  "history",
  "localhost",
  "127.0.0.1",
]) {
  if (serialized.includes(forbidden)) {
    throw new Error(`Forbidden extension capability found: ${forbidden}`);
  }
}

console.log(`Built Signal MV3 extension ${manifest.version} in ${outputRoot}`);
