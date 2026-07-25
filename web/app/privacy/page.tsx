import { ContentNav } from "../components/ContentNav";

export default function PrivacyPage() {
  return (
    <>
      <ContentNav />
      <main className="content-page" id="main-content">
      <div className="content-wrap">
        <p className="eyebrow">Privacy</p>
        <h1>Local vision. Explicit action.</h1>
        <p>
          Signal is designed around a simple boundary: hand tracking belongs on
          the Mac; cloud services receive only the text or profile data you choose to send.
        </p>
        <div className="content-grid">
          <article className="content-card"><span>ON DEVICE</span><h2>Camera frames</h2><p>Frames are processed in memory with Apple Vision. They are not uploaded, stored by the website, or accepted by the API.</p></article>
          <article className="content-card"><span>OPT IN</span><h2>Planning</h2><p>The planner receives a plain-language request and allowed action catalog. It does not receive camera data or secret values.</p></article>
          <article className="content-card"><span>REDACTED</span><h2>Shared profiles</h2><p>Prototype unlisted profiles use per-worker memory and may disappear between requests. They may keep secret reference IDs for configuration, but never webhook URLs, tokens, passwords, cookies, or authorization values. Only the seeded demo profile is durable in this release.</p></article>
          <article className="content-card"><span>DEFAULT OFF</span><h2>Telemetry</h2><p>No product telemetry is enabled by default. Output also starts paused, and the emergency shortcut closes every output gate.</p></article>
        </div>
      </div>
      </main>
    </>
  );
}
