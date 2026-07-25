import "@testing-library/jest-dom/vitest";

import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { SignalBuilder } from "../components/builder/SignalBuilder";
import { SignalDemo } from "../components/builder/SignalDemo";

beforeEach(() => {
  window.localStorage.clear();
  vi.stubGlobal("crypto", {
    randomUUID: vi.fn(() => "00000000-0000-4000-8000-000000000001"),
  });
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("SignalBuilder", () => {
  it("renders all nine labeled gestures and keeps selection visible", async () => {
    const user = userEvent.setup();
    render(<SignalBuilder />);

    const names = [
      "One",
      "Two",
      "Three",
      "Four",
      "Five",
      "Fist",
      "Thumbs up",
      "Thumbs down",
      "C shape",
    ];
    for (const name of names) {
      expect(
        screen.getByRole("button", { name: new RegExp(`^${name}`) }),
      ).toBeInTheDocument();
    }

    const thumbsUp = screen.getByRole("button", { name: /^Thumbs up/ });
    expect(thumbsUp).toHaveAttribute("aria-pressed", "true");

    const one = screen.getByRole("button", { name: /^One/ });
    await user.click(one);
    expect(one).toHaveAttribute("aria-pressed", "true");
    expect(thumbsUp).toHaveAttribute("aria-pressed", "false");
    expect(screen.getByText("Step 2 · One")).toBeInTheDocument();
    expect(
      screen.getByText(/Hybrid Mode keeps One for pointer control/),
    ).toBeInTheDocument();
  });

  it("surfaces a typed planner clarification without creating a preview", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          schemaVersion: 1,
          requestId: "00000000-0000-4000-8000-000000000001",
          status: "needs_clarification",
          question: "Which public HTTPS URL should Signal open?",
          missingFields: ["publicUrl"],
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    render(<SignalBuilder />);

    await user.click(screen.getByRole("button", { name: "Generate plan" }));

    expect(
      await screen.findByText("Which public HTTPS URL should Signal open?"),
    ).toBeInTheDocument();
    expect(screen.getByText("One detail needed")).toBeInTheDocument();
    expect(screen.getByText("No steps yet")).toBeInTheDocument();

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(JSON.parse(String(init.body))).toMatchObject({
      schemaVersion: 1,
      targetGesture: "thumbs_up",
      requestId: "00000000-0000-4000-8000-000000000001",
    });
  });

  it("reports strict import errors and never treats import as execution", async () => {
    const user = userEvent.setup();
    const { container } = render(<SignalBuilder />);
    const input = container.querySelector<HTMLInputElement>(
      'input[type="file"]',
    );
    expect(input).not.toBeNull();

    const file = new File(
      [JSON.stringify({ schemaVersion: 2, rawToken: "not-portable" })],
      "unsafe-profile.json",
      { type: "application/json" },
    );
    Object.defineProperty(file, "text", {
      value: async () =>
        JSON.stringify({ schemaVersion: 2, rawToken: "not-portable" }),
    });
    await user.upload(input as HTMLInputElement, file);

    expect(
      await screen.findByRole("alert"),
    ).toHaveTextContent(
      "This file is not a strict Signal version 1 profile. Unknown fields, actions, and versions are rejected.",
    );
    expect(screen.getByText("Nothing on this page runs a Mac command.")).toBe(
      screen.getByText("Nothing on this page runs a Mac command."),
    );
  });

  it("requires a public-summary review and shows the publishing warning", async () => {
    const user = userEvent.setup();
    render(<SignalBuilder />);

    await user.click(
      screen.getByRole("button", { name: /^Show notification/ }),
    );
    await user.click(
      screen.getByRole("button", { name: "Add reviewed step" }),
    );
    await user.click(
      await screen.findByRole("button", { name: "Save to Thumbs up" }),
    );
    expect(
      await screen.findByText(
        "Thumbs up saved locally. Nothing has run.",
      ),
    ).toBeInTheDocument();

    const reviewButton = screen.getByRole("button", {
      name: "Review & publish",
    });
    expect(reviewButton).toBeEnabled();
    await user.click(reviewButton);

    const dialog = screen.getByRole("dialog", {
      name: "Make this profile unlisted?",
    });
    expect(dialog).toHaveTextContent(
      "A share code is not authentication.",
    );
    expect(dialog).toHaveTextContent(
      "Signal sends no webhook URL, token, password, cookie, or camera data in a portable profile.",
    );

    const publishButton = screen.getByRole("button", {
      name: "Publish unlisted profile",
    });
    expect(publishButton).toBeDisabled();
    await user.click(
      screen.getByRole("checkbox", {
        name: /I reviewed the public summary/,
      }),
    );
    expect(publishButton).toBeEnabled();
  });

  it("keeps the create-only revoke token out of local storage and can revoke the share", async () => {
    const revokeToken = `SRV1_${"a".repeat(64)}`;
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            schemaVersion: 1,
            shareCode: "SIG1-ABCDEFGH",
            profileURL: "https://signal.example/p/SIG1-ABCDEFGH",
            revokeToken,
          }),
          {
            status: 201,
            headers: { "content-type": "application/json" },
          },
        ),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ schemaVersion: 1, revoked: true }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    vi.stubGlobal("fetch", fetchMock);
    vi.spyOn(window, "confirm").mockReturnValue(true);
    const user = userEvent.setup();
    render(<SignalBuilder />);

    await user.click(
      screen.getByRole("button", { name: /^Show notification/ }),
    );
    await user.click(screen.getByRole("button", { name: "Add reviewed step" }));
    await user.click(
      await screen.findByRole("button", { name: "Save to Thumbs up" }),
    );
    await user.click(
      screen.getByRole("button", { name: "Review & publish" }),
    );
    await user.click(
      screen.getByRole("checkbox", {
        name: /I reviewed the public summary/,
      }),
    );
    await user.click(
      screen.getByRole("button", { name: "Publish unlisted profile" }),
    );

    expect(
      await screen.findByRole("heading", { name: "SIG1-ABCDEFGH" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Copy revocation key" }),
    ).toBeInTheDocument();
    expect(screen.getByText(/only in memory on this open page/i)).toBeInTheDocument();
    expect(window.localStorage.getItem("signal.guest-profile.v1")).not.toContain(
      revokeToken,
    );

    await user.click(screen.getByRole("button", { name: "Revoke profile" }));
    expect(
      await screen.findByText(
        "Unlisted profile revoked. Its public link no longer resolves.",
      ),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "SIG1-ABCDEFGH" }),
    ).not.toBeInTheDocument();

    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [revokeUrl, revokeInit] = fetchMock.mock.calls[1] as [
      string,
      RequestInit,
    ];
    expect(revokeUrl).toBe(
      "/api/v1/profiles/SIG1-ABCDEFGH/revoke",
    );
    expect(JSON.parse(String(revokeInit.body))).toEqual({ revokeToken });
    expect(window.localStorage.getItem("signal.guest-profile.v1")).not.toContain(
      revokeToken,
    );
  });
});

describe("SignalDemo honest boundary", () => {
  it("labels the browser boundary before simulation", () => {
    render(<SignalDemo />);
    expect(screen.getByText("Page-local simulation")).toBeInTheDocument();
    expect(
      screen.getByText("Camera off · Mac control unavailable · No external effects"),
    ).toBeInTheDocument();
    expect(screen.getByText("External effects: 0")).toBeInTheDocument();
    expect(
      screen.getByRole("heading", {
        name: "The browser explains. The Mac app acts.",
      }),
    ).toBeInTheDocument();
  });

  it("finishes the Discord demo with a local fallback and zero system effects", async () => {
    vi.useFakeTimers();
    render(<SignalDemo />);

    fireEvent.click(
      screen.getByRole("button", { name: "Run Thumbs up simulation" }),
    );
    await act(async () => {
      await vi.advanceTimersByTimeAsync(600 + 3 * 450);
    });

    expect(
      screen.getByText(
        "Simulation complete. 3 simulated receipts. System actions performed: 0.",
      ),
    ).toBeInTheDocument();
    expect(screen.getByText("LOCAL FALLBACK")).toBeInTheDocument();
    expect(
      screen.getByText("Local fallback receipt — no message sent"),
    ).toBeInTheDocument();
    expect(screen.getByText("External effects: 0")).toBeInTheDocument();
  });
});
