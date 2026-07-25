import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { parseStoredProfile } from "../src/shared/schema";

const extensionRoot = process.cwd();

describe("release integration", () => {
  it("requests only the reviewed MV3 permissions", async () => {
    const manifest = JSON.parse(
      await readFile(resolve(extensionRoot, "manifest.json"), "utf8"),
    ) as {
      manifest_version: number;
      permissions: string[];
      host_permissions: string[];
    };
    expect(manifest.manifest_version).toBe(3);
    expect([...manifest.permissions].sort()).toEqual([
      "activeTab",
      "offscreen",
      "scripting",
      "sidePanel",
      "storage",
      "tabs",
    ]);
    expect(manifest.host_permissions).toEqual([
      "http://*/*",
      "https://*/*",
    ]);
    expect(JSON.stringify(manifest)).not.toMatch(
      /nativeMessaging|"debugger"|"history"/,
    );
  });

  it("ships a strict, importable browser-safe demo profile", async () => {
    const profile = JSON.parse(
      await readFile(resolve(extensionRoot, "demo-profile.json"), "utf8"),
    );
    expect(parseStoredProfile(profile)).toMatchObject({
      id: "signal.demo.extension",
      commands: [{ gesture: "fist", enabled: true }],
    });
  });

  it("documents install, release, and protected-page boundaries", async () => {
    const documents = await Promise.all(
      ["README.md", "RELEASE_NOTES.md", "KNOWN_LIMITATIONS.md"].map((path) =>
        readFile(resolve(extensionRoot, path), "utf8"),
      ),
    );
    expect(documents[0]).toContain("Load unpacked");
    expect(documents[1]).toContain("Manifest V3");
    expect(documents[2]).toContain("chrome://");
    expect(documents.join("\n")).not.toContain("zero-install");
  });
});
