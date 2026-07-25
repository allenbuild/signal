import { ContentNav } from "../components/ContentNav";

export default function PriorWorkPage() {
  return (
    <main className="content-page">
      <ContentNav />
      <div className="content-wrap">
        <p className="eyebrow">Night Hack disclosure</p>
        <h1>Built on HandPilot. Extended as Signal.</h1>
        <p>
          Before Night Hack, the team built a separate native macOS experiment named
          HandPilot. The disclosed baseline included camera capture, Apple Vision hand
          landmark tracking, a deterministic gesture engine, macOS input event generation,
          permissions and safety handling, calibration diagnostics, and touchless pointer,
          click, scroll, and zoom controls.
        </p>
        <p>
          During Night Hack, the team created Signal as a substantial new capability layer
          and product: nine programmable gestures, natural-language workflow creation,
          Teach by Demo recording, an editable macro engine, action integrations, profiles,
          sharing, cloud planning, a redesigned command-centered experience, public
          deployment, and distributable release packaging.
        </p>
        <p>
          Repository evidence and team disclosure are kept separate: the inspected
          <code> night-hack-start </code> commit contains zero tracked files, so the
          HandPilot capability description above is team-supplied disclosure rather
          than behavior verified from source at that tag.
        </p>
        <div className="download-panel">
          <h2>A visible baseline</h2>
          <p>The repository’s <code>night-hack-start</code> tag marks the complete pre-event baseline. Only commits after that tag are claimed as Night Hack work.</p>
        </div>
      </div>
    </main>
  );
}
