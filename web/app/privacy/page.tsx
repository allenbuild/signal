import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy",
  description: "How Signal keeps camera input, plans, profiles, and secrets private.",
};

const rows = [
  ["Camera frames", "Memory-only in the native Mac app", "Never uploaded by this service"],
  ["Hand landmarks and gesture state", "Processed locally", "Not stored by default"],
  ["Planner text", "Sent only when you choose Generate", "Used to return a reviewed plan"],
  ["Profiles", "Local until you export or publish", "Unlisted shares contain redacted profile data"],
  ["Integration secrets", "Keychain or managed server environment", "Never portable profile JSON"],
  ["Telemetry", "Off by default", "No camera or raw recording telemetry"],
] as const;

export default function PrivacyPage() {
  return (
    <main id="main-content" className="page-main">
      <section className="page-hero shell">
        <p className="eyebrow">Privacy</p>
        <h1>Your camera is not cloud input.</h1>
        <p>
          The website builds and shares commands. The Mac app observes your hand
          locally. Camera frames do not cross that boundary.
        </p>
      </section>
      <section className="shell policy-table" aria-label="Signal data handling">
        <div className="policy-row policy-head">
          <span>Data</span><span>Where it lives</span><span>Cloud behavior</span>
        </div>
        {rows.map(([data, location, behavior]) => (
          <div className="policy-row" key={data}>
            <strong>{data}</strong><span>{location}</span><span>{behavior}</span>
          </div>
        ))}
      </section>
      <section className="section shell prose-grid">
        <article>
          <p className="eyebrow">Sharing</p>
          <h2>Nothing becomes public by accident.</h2>
          <p>
            Guest profiles stay in your browser until you export them. Publishing
            creates an unlisted, read-only link after showing exactly what will
            be shared. Raw tokens, webhook URLs, passwords, cookies, and
            credential-like fields are rejected.
          </p>
        </article>
        <article>
          <p className="eyebrow">Secrets</p>
          <h2>References travel. Values do not.</h2>
          <p>
            Plans can name a secret reference such as a Discord connection.
            The actual value is resolved from Keychain or the service
            environment at execution time and is never returned in a profile,
            receipt, share code, or planner response.
          </p>
        </article>
      </section>
    </main>
  );
}
