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
          Before Night Hack, the team built a separate native experiment named
          HandPilot with early pointer, click, scroll, and zoom work. That
          prototype is prior work; it is not the architecture shipped by the
          Signal Chrome extension.
        </p>
      </section>
      <section className="section shell prose-grid">
        <article>
          <p className="eyebrow">Signal additions</p>
          <h2>A programmable command layer.</h2>
          <p>
            During Night Hack, Signal gained local MediaPipe hand tracking,
            Control and Commands modes, nine deterministic command gestures,
            natural-language workflow creation, Teach by Demo, reviewed
            browser-safe plans, typed integrations, durable profile sharing,
            deployment, and tests. The final runtime packages those capabilities
            as one cross-tab Manifest V3 Chrome extension.
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
