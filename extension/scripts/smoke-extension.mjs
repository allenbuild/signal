import { createServer } from "node:http";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";

import { chromium } from "@playwright/test";

const extensionRoot = resolve(import.meta.dirname, "..");
const extensionPath = resolve(extensionRoot, "dist");
const userDataDir = await mkdtemp(resolve(tmpdir(), "signal-extension-smoke-"));

const server = createServer((_request, response) => {
  response.writeHead(200, {
    "content-type": "text/html; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(`<!doctype html>
    <html>
      <head><title>Signal extension fixture</title></head>
      <body style="min-height:2400px">
        <button id="target" onclick="this.dataset.clicked='true'">Target</button>
        <input id="search" aria-label="Search" />
        <div id="result">ready</div>
      </body>
    </html>`);
});

await new Promise((resolvePromise, reject) => {
  server.once("error", reject);
  server.listen(0, "127.0.0.1", resolvePromise);
});
const address = server.address();
if (!address || typeof address === "string") {
  throw new Error("Signal fixture server did not expose a TCP port.");
}
const fixtureUrl = `http://127.0.0.1:${address.port}/fixture`;

let context;
try {
  context = await chromium.launchPersistentContext(userDataDir, {
    headless: false,
    args: [
      `--disable-extensions-except=${extensionPath}`,
      `--load-extension=${extensionPath}`,
      "--no-first-run",
      "--no-default-browser-check",
      "--use-fake-device-for-media-stream",
      "--use-fake-ui-for-media-stream",
    ],
  });

  let worker = context.serviceWorkers()[0];
  worker ??= await context.waitForEvent("serviceworker", { timeout: 15_000 });
  const extensionId = new URL(worker.url()).host;
  if (!extensionId) throw new Error("Signal extension ID was not resolved.");

  const controlledPage = await context.newPage();
  await controlledPage.goto(fixtureUrl);
  await controlledPage.waitForSelector("#signal-extension-overlay", {
    timeout: 10_000,
  });
  const overlayCount = await controlledPage
    .locator("#signal-extension-overlay")
    .count();
  if (overlayCount !== 1) {
    throw new Error(`Expected one Signal overlay, found ${overlayCount}.`);
  }

  await controlledPage.reload();
  await controlledPage.waitForSelector("#signal-extension-overlay");
  if (
    (await controlledPage.locator("#signal-extension-overlay").count()) !== 1
  ) {
    throw new Error("Signal overlay was duplicated after navigation.");
  }

  const controlledTabUrl = controlledPage.url();
  const panel = await context.newPage();
  await panel.goto(`chrome-extension://${extensionId}/sidepanel/index.html`);
  await panel.getByRole("heading", { name: "signal", exact: true }).waitFor();
  await panel.getByRole("button", { name: "Start Signal" }).waitFor();

  const runtimeStatus = await panel.evaluate(async () => {
    return chrome.runtime.sendMessage({
      version: 1,
      type: "signal:sidepanel/status",
    });
  });
  if (!runtimeStatus?.ok) {
    throw new Error("The Signal service worker did not answer the side panel.");
  }

  const permissionPagePromise = context.waitForEvent("page");
  await panel.getByRole("button", { name: "Start Signal" }).click();
  const permissionPage = await permissionPagePromise;
  await permissionPage.waitForURL(
    `chrome-extension://${extensionId}/setup/setup.html`,
  );
  await permissionPage
    .getByRole("button", { name: "Allow camera for Signal" })
    .click();
  await panel
    .locator(".camera-pill")
    .filter({ hasText: /FPS/ })
    .waitFor({ timeout: 30_000 });
  let cameraFps = 0;
  const cameraDeadline = Date.now() + 5_000;
  while (cameraFps <= 0 && Date.now() < cameraDeadline) {
    cameraFps = Number.parseFloat(
      (await panel.locator(".camera-pill").textContent()) ?? "0",
    );
    if (cameraFps <= 0) await panel.waitForTimeout(250);
  }
  if (cameraFps <= 0) {
    throw new Error("The offscreen camera opened but processed no frames.");
  }

  const receipt = await panel.evaluate(async (url) => {
    const tabs = await chrome.tabs.query({});
    const tab = tabs.find((candidate) => candidate.url === url);
    if (tab?.id === undefined) throw new Error("Controlled fixture tab missing.");
    return chrome.tabs.sendMessage(tab.id, {
      version: 1,
      type: "signal:content-action",
      requestId: "browser-smoke-click",
      action: {
        type: "click_selector",
        parameters: { selector: "#target" },
      },
    });
  }, controlledTabUrl);
  if (!receipt?.ok) {
    throw new Error(receipt?.message ?? "Content action did not complete.");
  }
  if ((await controlledPage.locator("#target").getAttribute("data-clicked")) !== "true") {
    throw new Error("The built content script did not click the fixture target.");
  }

  const stopReceipt = await panel.evaluate(async () => {
    return chrome.runtime.sendMessage({
      version: 1,
      type: "signal:sidepanel/stop",
    });
  });
  if (!stopReceipt?.ok) {
    throw new Error(stopReceipt?.error ?? "Signal did not stop cleanly.");
  }
  await panel.getByRole("button", { name: "Start Signal" }).waitFor();

  console.log(
    JSON.stringify(
      {
        extensionId,
        serviceWorker: true,
        overlaySingleton: true,
        navigationReset: true,
        sidePanel: true,
        syntheticCameraActive: true,
        syntheticProcessedFps: cameraFps,
        cameraStopped: true,
        contentAction: "click_selector",
      },
      null,
      2,
    ),
  );
} finally {
  await context?.close();
  await new Promise((resolvePromise) => server.close(resolvePromise));
  await rm(userDataDir, { recursive: true, force: true });
}
