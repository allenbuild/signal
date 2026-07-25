import { expect, test, type Page, type TestInfo } from "@playwright/test";

const fallbackBaseURL =
  process.env.PLAYWRIGHT_BASE_URL ??
  process.env.BASE_URL ??
  "http://127.0.0.1:3000";

const gestureIds = [
  "one",
  "two",
  "three",
  "four",
  "five",
  "thumbs_up",
  "thumbs_down",
  "c_shape",
  "fist",
] as const;

function appURL(pathname: string, testInfo: TestInfo) {
  const configuredBaseURL = testInfo.project.use.baseURL;
  const baseURL =
    typeof configuredBaseURL === "string" ? configuredBaseURL : fallbackBaseURL;
  return new URL(pathname, baseURL).toString();
}

async function openSignal(page: Page, testInfo: TestInfo) {
  const response = await page.goto(appURL("/", testInfo), {
    waitUntil: "domcontentloaded",
  });
  expect(response).not.toBeNull();
  expect(response?.ok()).toBe(true);
  await expect(
    page.getByRole("heading", { level: 1, name: "signal", exact: true }),
  ).toBeVisible();
  await page.waitForFunction(
    () => typeof window.signalGestureBridge?.emit === "function",
  );
}

function fistCard(page: Page) {
  return page.locator('button[data-gesture="fist"]');
}

async function openFistEditor(page: Page) {
  await fistCard(page).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await expect(
    dialog.getByRole("heading", {
      level: 2,
      name: /Tell Signal what to do\.|Confirm every step\./,
    }),
  ).toBeVisible();
  return dialog;
}

async function generateFallbackPlan(page: Page) {
  const dialog = page.getByRole("dialog");
  await expect(
    dialog.getByLabel("What should happen when you make a fist?"),
  ).toHaveValue(
    /open Spotify, wait one second, and start my focus playlist/i,
  );
  await dialog
    .getByRole("button", { name: "Generate structured command" })
    .click();
  await expect(
    dialog.getByRole("heading", { level: 2, name: "Confirm every step." }),
  ).toBeVisible();
  await expect(
    dialog.getByText("Deterministic fallback", { exact: true }),
  ).toBeVisible();
  await expect(
    dialog.getByText(/Claude was not used/i),
  ).toBeVisible();
}

test.describe("signal single-page command interface", () => {
  test("renders the exact lowercase title and all nine gestures with a centered fist", async ({
    page,
  }, testInfo) => {
    await openSignal(page, testInfo);

    const title = page.getByRole("heading", {
      level: 1,
      name: "signal",
      exact: true,
    });
    await expect(title).toHaveText("signal");
    await expect(page.getByRole("heading", { level: 1 })).toHaveCount(1);

    const presetGrid = page.getByLabel("Preset gesture commands");
    await expect(presetGrid.locator("button[data-gesture]")).toHaveCount(8);
    await expect(page.locator("button[data-gesture]")).toHaveCount(9);

    const renderedGestures = await page
      .locator("button[data-gesture]")
      .evaluateAll((cards) => cards.map((card) => card.getAttribute("data-gesture")));
    expect(new Set(renderedGestures)).toEqual(new Set(gestureIds));

    await expect(fistCard(page)).toHaveCount(1);
    const stageBox = await page.locator(".signal-command-stage").boundingBox();
    const fistBox = await fistCard(page).boundingBox();
    expect(stageBox).not.toBeNull();
    expect(fistBox).not.toBeNull();
    const stageCenter = stageBox!.x + stageBox!.width / 2;
    const fistCenter = fistBox!.x + fistBox!.width / 2;
    expect(Math.abs(stageCenter - fistCenter)).toBeLessThan(5);
  });

  test("preset cards open a locked preview while Fist alone opens the editor", async ({
    page,
  }, testInfo) => {
    await openSignal(page, testInfo);

    await page.getByRole("button", { name: "One: Open Spotify" }).click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    await expect(
      page.getByText(/Locked preset · Open app/i),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { level: 2, name: "Open Spotify" }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Close preset preview" }),
    ).toBeVisible();

    await openFistEditor(page);
    await expect(
      page.getByRole("dialog").getByText("Create fist command", { exact: true }),
    ).toBeVisible();
  });

  test("fallback review saves a custom Fist command and restores it after reload", async ({
    page,
  }, testInfo) => {
    await openSignal(page, testInfo);
    await openFistEditor(page);
    await generateFallbackPlan(page);

    const dialog = page.getByRole("dialog");
    const commandName = dialog.getByLabel("Command name");
    await commandName.fill("Launch deep work");
    await expect(
      dialog.getByText(/Saving does not execute it/i),
    ).toBeVisible();
    await dialog.getByRole("button", { name: "Save to Fist" }).click();

    await expect(page.getByRole("dialog")).toHaveCount(0);
    await expect(
      page.getByRole("button", { name: "Fist: Launch deep work" }),
    ).toBeVisible();
    await expect(
      page.getByText("Launch deep work assigned to Fist and saved locally."),
    ).toBeVisible();

    const stored = await page.evaluate(() => {
      const raw = window.localStorage.getItem("signal.fist-command.v1");
      return raw ? JSON.parse(raw) : null;
    });
    expect(stored).toMatchObject({
      storageVersion: 1,
      command: {
        schemaVersion: 1,
        gesture: "fist",
        name: "Launch deep work",
        source: "natural_language",
      },
    });

    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(
      page.getByRole("heading", { level: 1, name: "signal", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Fist: Launch deep work" }),
    ).toBeVisible();
  });

  for (const recordingCase of ["unsupported", "denied"] as const) {
    test(`recording ${recordingCase} path remains recoverable with natural language`, async ({
      page,
    }, testInfo) => {
      await page.addInitScript((scenario) => {
        if (scenario === "unsupported") {
          Object.defineProperty(navigator, "mediaDevices", {
            configurable: true,
            value: {},
          });
          Object.defineProperty(window, "MediaRecorder", {
            configurable: true,
            value: undefined,
          });
          return;
        }

        Object.defineProperty(navigator, "mediaDevices", {
          configurable: true,
          value: {
            getDisplayMedia: () =>
              Promise.reject(
                new DOMException("Permission denied for test", "NotAllowedError"),
              ),
          },
        });
        Object.defineProperty(window, "MediaRecorder", {
          configurable: true,
          value: class MockMediaRecorder {
            static isTypeSupported() {
              return true;
            }
          },
        });
      }, recordingCase);

      await openSignal(page, testInfo);
      const dialog = await openFistEditor(page);
      await dialog.getByRole("button", { name: "Start recording" }).click();

      await expect(
        dialog.getByRole("alert").filter({
          hasText:
            recordingCase === "unsupported"
              ? /Screen recording is unavailable in this browser/i
              : /Screen sharing was cancelled or denied/i,
        }),
      ).toBeVisible();
      await expect(
        dialog.getByLabel("What should happen when you make a fist?"),
      ).toBeEditable();
      await expect(
        dialog.getByRole("button", { name: "Generate structured command" }),
      ).toBeEnabled();

      await generateFallbackPlan(page);
      await expect(
        dialog.getByRole("button", { name: "Save to Fist" }),
      ).toBeEnabled();
    });
  }

  test("normalized gesture events highlight cards and are ignored while the editor is open", async ({
    page,
  }, testInfo) => {
    await openSignal(page, testInfo);

    const twoCard = page.locator('button[data-gesture="two"]');
    await page.evaluate(() => {
      window.dispatchEvent(
        new CustomEvent("signal:gesture", {
          detail: {
            gesture: "two",
            confidence: 0.96,
            phase: "holding",
            progress: 0.72,
            timestamp: Date.now(),
          },
        }),
      );
    });
    await expect(twoCard).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("status")).toContainText(
      "Two detected at 96% confidence.",
    );

    const dialog = await openFistEditor(page);
    const statusBefore = await page.getByRole("status").first().textContent();
    const threeCard = page.locator('button[data-gesture="three"]');
    await page.evaluate(() => {
      window.dispatchEvent(
        new CustomEvent("signal:gesture", {
          detail: {
            gesture: "three",
            confidence: 0.99,
            phase: "recognized",
            progress: 1,
            timestamp: Date.now(),
          },
        }),
      );
    });
    await page.waitForTimeout(100);
    await expect(threeCard).toHaveAttribute("aria-pressed", "false");
    await expect(page.getByRole("status").first()).toHaveText(statusBefore ?? "");

    await dialog
      .getByRole("button", { name: "Close custom command editor" })
      .click();
    await expect(dialog).toHaveCount(0);
    await page.waitForTimeout(50);
    await page.evaluate(() => {
      window.dispatchEvent(
        new CustomEvent("signal:gesture", {
          detail: {
            gesture: "three",
            confidence: 0.99,
            phase: "recognized",
            progress: 1,
            timestamp: Date.now() + 1_000,
          },
        }),
      );
    });
    await expect(threeCard).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("status")).toContainText(
      "Three command fired.",
    );
  });

  test("mobile viewport has no horizontal overflow", async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 393, height: 852 });
    await openSignal(page, testInfo);

    const dimensions = await page.evaluate(() => ({
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }));
    expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth);
    await expect(page.locator("button[data-gesture]")).toHaveCount(9);
    await expect(fistCard(page)).toBeVisible();
  });

  test("health endpoint returns the stable non-secret version 1 envelope", async ({
    request,
  }, testInfo) => {
    const response = await request.get(appURL("/api/v1/health", testInfo));

    expect(response.status()).toBe(200);
    expect(response.headers()["content-type"]).toContain("application/json");
    expect(response.headers()["x-request-id"]).toBeTruthy();
    await expect(response.json()).resolves.toEqual({
      schemaVersion: 1,
      status: "ok",
    });
  });
});
