import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

const runtimeFiles = [
  resolve(process.cwd(), "src/offscreen/camera-runtime.ts"),
  resolve(process.cwd(), "src/offscreen/mediapipe-runtime.ts"),
  resolve(process.cwd(), "src/offscreen/offscreen.ts"),
];

describe("offscreen privacy boundary", () => {
  it("contains no live-frame upload, recording, or persistence primitive", async () => {
    const source = (
      await Promise.all(runtimeFiles.map((file) => readFile(file, "utf8")))
    ).join("\n");

    expect(source).not.toMatch(/\bfetch\s*\(/);
    expect(source).not.toMatch(/\bsendBeacon\s*\(/);
    expect(source).not.toMatch(/\bXMLHttpRequest\b/);
    expect(source).not.toMatch(/\bWebSocket\b/);
    expect(source).not.toMatch(/\bMediaRecorder\b/);
    expect(source).not.toMatch(/\bchrome\.storage\b/);
  });

  it("resolves every MediaPipe binary from the packaged extension", async () => {
    const source = await readFile(runtimeFiles[1]!, "utf8");

    expect(source).toContain("chrome.runtime.getURL");
    expect(source).not.toMatch(/https?:\/\//);
  });
});
