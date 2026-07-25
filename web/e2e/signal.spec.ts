import { expect, test, type TestInfo } from "@playwright/test";

const fallbackBaseURL =
  process.env.PLAYWRIGHT_BASE_URL ??
  process.env.BASE_URL ??
  "http://localhost:3000";

function appURL(pathname: string, testInfo: TestInfo) {
  const configuredBaseURL = testInfo.project.use.baseURL;
  const baseURL =
    typeof configuredBaseURL === "string" ? configuredBaseURL : fallbackBaseURL;
  return new URL(pathname, baseURL).toString();
}

test.describe("Signal download site", () => {
  test("contains only the extension download experience", async ({
    page,
  }, testInfo) => {
    const response = await page.goto(appURL("/", testInfo), {
      waitUntil: "domcontentloaded",
    });
    expect(response?.ok()).toBe(true);
    await expect(
      page.getByRole("heading", { level: 1, name: "signal", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Four quick steps" }),
    ).toBeVisible();
    await expect(page.getByText("chrome://extensions")).toBeVisible();
    await expect(page.getByText("Load unpacked")).toBeVisible();
    await expect(page.getByRole("link")).toHaveCount(1);

    const downloadLink = page.getByRole("link", {
      name: /Download extension/i,
    });
    await expect(downloadLink).toHaveAttribute(
      "href",
      "/downloads/signal-extension.zip?v=0.3.1",
    );
    const downloadPromise = page.waitForEvent("download");
    await downloadLink.click();
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toBe("signal-extension.zip");
  });

  test("redirects former public UI routes to the download page", async ({
    page,
  }, testInfo) => {
    for (const pathname of [
      "/builder",
      "/demo",
      "/docs",
      "/prior-work",
      "/privacy",
      "/security",
      "/setup",
      "/p/example",
    ]) {
      await page.goto(appURL(pathname, testInfo), {
        waitUntil: "domcontentloaded",
      });
      await expect(page).toHaveURL(appURL("/", testInfo));
      await expect(
        page.getByRole("link", { name: /Download extension/i }),
      ).toBeVisible();
    }
  });
});
