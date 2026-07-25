import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Prior work",
  description: "The evidence boundary between HandPilot and Signal.",
};

export default function PriorWorkPage() {
  return (
    <main className="page-main" id="main-content">
      <section className="page-hero shell">
        <p className="eyebrow">Night Hack disclosure</p>
        <h1>Built on HandPilot. Extended as Signal.</h1>
        <p>
          Before Night Hack, the team built a separate native macOS experiment
          named HandPilot. The disclosed baseline included camera capture,
          Apple Vision hand-landmark tracking, deterministic gestures, macOS
          input events, permission and safety handling, calibration diagnostics,
          and touchless pointer, click, scroll, and zoom controls.
        </p>
      </section>
      <section className="section shell prose-grid">
        <article>
          <p className="eyebrow">Signal additions</p>
          <h2>A programmable command layer.</h2>
          <p>
            Signal adds nine programmable gestures, natural-language workflow
            creation, Teach by Demo, validated macro planning, typed
            integrations, durable profile sharing, a public command interface,
            and native release packaging.
          </p>
        </article>
        <article>
          <p className="eyebrow">Repository evidence</p>
          <h2>A visible baseline.</h2>
          <p>
            The inspected <code>night-hack-start</code> commit contains zero
            tracked files. The HandPilot description is team-supplied
            disclosure; implementation and verification claims for Signal are
            tied to the source and test evidence added after that tag.
          </p>
        </article>
      </section>
    </main>
  );
}
