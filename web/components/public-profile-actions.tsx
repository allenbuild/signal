"use client";

import { useState } from "react";
import { profileSchema } from "../lib/contracts";

export function PublicProfileActions({ shareCode }: { shareCode: string }) {
  const [notice, setNotice] = useState("");

  async function copy(value: string, message: string) {
    try {
      await navigator.clipboard.writeText(value);
      setNotice(message);
    } catch {
      setNotice("Copy was unavailable. Select the code manually.");
    }
  }

  async function importIntoBuilder() {
    setNotice("Validating the shared profile…");
    try {
      const response = await fetch(`/api/v1/profiles/${shareCode}`);
      if (!response.ok) throw new Error("unavailable");
      const parsed = profileSchema.safeParse(await response.json());
      if (!parsed.success) throw new Error("invalid");
      const profile = parsed.data;
      window.localStorage.setItem(
        "signal.guest-profile.v1",
        JSON.stringify({
          ...profile,
          id: `signal.import.${Date.now()}`,
          share: { visibility: "private" },
        }),
      );
      window.location.assign("/builder");
    } catch {
      setNotice("This profile could not be imported.");
    }
  }

  return (
    <div className="public-profile-actions">
      <button
        className="button button-primary"
        type="button"
        onClick={() => void importIntoBuilder()}
      >
        Use in Builder
      </button>
      <button
        className="button button-secondary"
        type="button"
        onClick={() => void copy(shareCode, "Share code copied.")}
      >
        Copy share code
      </button>
      <a
        className="button button-secondary"
        href={`/api/v1/profiles/${shareCode}`}
        download={`${shareCode}.json`}
      >
        Download JSON
      </a>
      <p role="status" aria-live="polite">{notice}</p>
    </div>
  );
}
