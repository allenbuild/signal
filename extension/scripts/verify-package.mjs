import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { readFile, readdir, stat } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const extensionRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const distRoot = resolve(extensionRoot, "dist");
const unpackedRoot = resolve(distRoot, "signal-extension");
const zipPath = resolve(distRoot, "signal-extension.zip");
const checksumPath = `${zipPath}.sha256`;

async function regularFiles(root) {
  const results = [];
  const visit = async (directory) => {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const absolute = resolve(directory, entry.name);
      if (entry.isDirectory()) {
        await visit(absolute);
      } else if (entry.isFile()) {
        results.push(relative(root, absolute).split(sep).join("/"));
      }
    }
  };
  await visit(root);
  return results.sort();
}

const manifestPath = resolve(unpackedRoot, "manifest.json");
if (!(await stat(manifestPath)).isFile()) {
  throw new Error("The unpacked extension does not contain root manifest.json.");
}
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
if (manifest.manifest_version !== 3) {
  throw new Error("The packaged extension manifest is not Manifest V3.");
}

const { stdout: zipListing } = await execFileAsync("unzip", ["-Z1", zipPath], {
  maxBuffer: 8 * 1024 * 1024,
});
const archiveEntries = zipListing
  .split(/\r?\n/)
  .filter(Boolean);
const archiveFiles = archiveEntries.filter((entry) => !entry.endsWith("/")).sort();

if (!archiveFiles.includes("manifest.json")) {
  throw new Error("The ZIP does not contain manifest.json at its root.");
}
if (
  archiveFiles.some(
    (entry) =>
      entry.startsWith("/") ||
      entry.startsWith("../") ||
      entry.includes("/../") ||
      entry.startsWith("signal-extension/"),
  )
) {
  throw new Error("The ZIP contains a nested or unsafe archive path.");
}

const unpackedFiles = await regularFiles(unpackedRoot);
if (JSON.stringify(archiveFiles) !== JSON.stringify(unpackedFiles)) {
  throw new Error("ZIP contents do not exactly match dist/signal-extension/.");
}

const { stdout: archivedManifest } = await execFileAsync(
  "unzip",
  ["-p", zipPath, "manifest.json"],
  { maxBuffer: 1024 * 1024 },
);
if (archivedManifest !== (await readFile(manifestPath, "utf8"))) {
  throw new Error("The archived and unpacked manifests differ.");
}

const zipBytes = await readFile(zipPath);
const actualDigest = createHash("sha256").update(zipBytes).digest("hex");
const checksum = (await readFile(checksumPath, "utf8")).trim();
const match = checksum.match(/^([a-f0-9]{64}) {2}signal-extension\.zip$/);
if (!match || match[1] !== actualDigest) {
  throw new Error("signal-extension.zip.sha256 does not match the ZIP.");
}

console.log(
  JSON.stringify(
    {
      unpacked: unpackedRoot,
      zip: zipPath,
      checksum: checksumPath,
      manifestAtArchiveRoot: true,
      files: archiveFiles.length,
      sha256: actualDigest,
    },
    null,
    2,
  ),
);
