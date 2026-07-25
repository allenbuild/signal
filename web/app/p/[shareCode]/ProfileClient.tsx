"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

type Profile = {
  name: string;
  description: string;
  preferredMode: string;
  hybridOneBehavior: string;
  mappings: Array<{
    gesture: string;
    plan: { name: string; description: string; steps: unknown[] };
  }>;
};

const symbols: Record<string, string> = {
  one: "01", two: "02", three: "03", four: "04", five: "05",
  fist: "●", thumbs_up: "↑", thumbs_down: "↓", c_shape: "C",
};

export function ProfileClient({ shareCode }: { shareCode: string }) {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [missing, setMissing] = useState(false);

  useEffect(() => {
    fetch(`/api/v1/profiles/${encodeURIComponent(shareCode)}`)
      .then(async (response) => {
        if (!response.ok) throw new Error("missing");
        return response.json() as Promise<Profile>;
      })
      .then(setProfile)
      .catch(() => setMissing(true));
  }, [shareCode]);

  return (
    <main className="profile-page">
      <div className="profile-shell">
        <div className="profile-top">
          <Link className="brand brand-light" href="/"><span className="brand-mark"><i /><i /><i /></span><span>Signal</span></Link>
          <Link className="button button-small button-primary" href="/download">Get Signal</Link>
        </div>
        {profile ? (
          <section className="profile-card">
            <div className="profile-hero">
              <span className="profile-code">UNLISTED PROFILE / {shareCode.toUpperCase()}</span>
              <h1>{profile.name}</h1>
              <p>{profile.description}</p>
              <div className="profile-meta"><span>{profile.preferredMode} mode</span><span>{profile.mappings.length} mappings</span><span>Schema v1</span></div>
            </div>
            <div className="mapping-list">
              <h2>GESTURE MAPPINGS</h2>
              {profile.mappings.map((mapping) => (
                <article className="mapping-item" key={mapping.gesture}>
                  <span className="mapping-icon">{symbols[mapping.gesture] ?? "·"}</span>
                  <div><h3>{mapping.plan.name}</h3><p>{mapping.gesture.replaceAll("_", " ")} · {mapping.plan.steps.length} validated actions</p></div>
                  <span>REVIEW TO IMPORT</span>
                </article>
              ))}
            </div>
          </section>
        ) : (
          <div className="profile-card profile-loading">
            {missing ? "This profile was not found or is no longer shared." : "Loading shared profile…"}
          </div>
        )}
      </div>
    </main>
  );
}
