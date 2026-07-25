import type { Metadata } from "next";
import { getReleaseMetadata } from "../../lib/release";

export const metadata: Metadata = {
  title: "Download",
  description: "Verified Signal for macOS release details and setup steps.",
};

function Fact({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="release-fact">
      <dt>{label}</dt>
      <dd>{value ?? "Verification pending"}</dd>
    </div>
  );
}

export default function DownloadPage() {
  const release = getReleaseMetadata();
  const isVerified = Boolean(
    release.downloadUrl && release.version && release.checksum,
  );

  return (
    <main id="main-content" className="page-main">
      <section className="page-hero shell">
        <p className="eyebrow">Signal for macOS</p>
        <h1>Download the exact build.</h1>
        <p>
          This page links an artifact only after its public download and
          checksum have been verified. No placeholder builds, no stale links.
        </p>
      </section>

      <section className="shell download-layout">
        <article className="release-card">
          <div className="release-card-heading">
            <div>
              <p className="eyebrow">Current release</p>
              <h2>{release.version ? `Signal ${release.version}` : "Verification in progress"}</h2>
            </div>
            <span className={`verification-chip ${isVerified ? "verified" : ""}`}>
              {isVerified ? "Verified artifact" : "Not yet published"}
            </span>
          </div>
          <dl className="release-facts">
            <Fact label="Filename" value={release.filename} />
            <Fact label="Commit" value={release.commit} />
            <Fact label="Minimum macOS" value={release.minimumMacOS} />
            <Fact label="Architecture" value={release.architecture} />
            <Fact label="Signing" value={release.signingStatus} />
            <Fact label="Notarization" value={release.notarizationStatus} />
            <Fact label="SHA-256" value={release.checksum} />
          </dl>
          {isVerified ? (
            <a className="button button-primary release-button" href={release.downloadUrl!}>
              Download {release.filename ?? "Signal"} <span aria-hidden="true">↓</span>
            </a>
          ) : (
            <button className="button button-disabled release-button" disabled>
              Release verification in progress
            </button>
          )}
        </article>

        <aside className="setup-note">
          <p className="eyebrow">Before you install</p>
          <p>
            Signal needs Camera access to see your hand and Accessibility access
            to control the pointer and approved actions.
          </p>
          <p>macOS 13 or later is required by the current native package.</p>
          <p>
            Output starts paused. You explicitly enable it after permissions are
            granted.
          </p>
        </aside>
      </section>

      <section className="section shell">
        <div className="section-heading split-heading">
          <div>
            <p className="eyebrow">Setup</p>
            <h2>From download to first gesture.</h2>
          </div>
          <p>Use the narrowest permission path. Never disable Gatekeeper globally.</p>
        </div>
        <ol className="install-steps">
          <li><span>01</span><div><h3>Install</h3><p>Download Signal, unzip it if needed, and move Signal to Applications.</p></div></li>
          <li><span>02</span><div><h3>Allow Camera</h3><p>Open Signal, then allow it in System Settings → Privacy &amp; Security → Camera.</p></div></li>
          <li><span>03</span><div><h3>Allow Accessibility</h3><p>Enable Signal in Privacy &amp; Security → Accessibility, then return to the app.</p></div></li>
          <li><span>04</span><div><h3>Enable output</h3><p>Review the safety state and explicitly enable output. The emergency stop pauses it immediately.</p></div></li>
        </ol>
        <details className="troubleshooting">
          <summary>Gatekeeper says Signal cannot be opened</summary>
          <p>
            If this release is honestly labeled unnotarized, Control-click Signal
            in Finder, choose Open, then choose Open again. Do not disable
            Gatekeeper globally.
          </p>
        </details>
        <details className="troubleshooting">
          <summary>Camera or Accessibility remains inactive</summary>
          <p>
            Confirm the permission is granted to the copy in Applications,
            fully quit Signal, and reopen it. Moving or replacing the app can
            require permission confirmation again.
          </p>
        </details>
      </section>
    </main>
  );
}
