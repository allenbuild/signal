import { ContentNav } from "../components/ContentNav";

export const dynamic = "force-dynamic";

export default function DownloadPage() {
  const downloadURL = process.env.SIGNAL_DOWNLOAD_URL;
  const version = process.env.SIGNAL_RELEASE_VERSION ?? "Not published";
  const commit = process.env.SIGNAL_RELEASE_COMMIT ?? "Not published";
  const checksum = process.env.SIGNAL_RELEASE_SHA256 ?? "Not published";
  const architecture = process.env.SIGNAL_RELEASE_ARCHITECTURE ?? "Apple silicon (arm64) only";
  const signingStatus = process.env.SIGNAL_SIGNING_STATUS ?? "Not declared";
  const notarizationStatus = process.env.SIGNAL_NOTARIZATION_STATUS ?? "Not declared";
  const isAdHoc =
    /ad[\s-]?hoc|unsigned/i.test(signingStatus) ||
    /ad[\s-]?hoc|not notarized/i.test(notarizationStatus);
  return (
    <>
      <ContentNav />
      <main className="content-page" id="main-content">
      <div className="content-wrap">
        <p className="eyebrow">Signal for macOS</p>
        <h1>Put your hand to work.</h1>
        <p>
          Signal is a native macOS app using Apple Vision and public input APIs.
          It does not need a localhost server. macOS 13 or later is required;
          the current artifact is Apple silicon only.
        </p>
        <div className="download-panel">
          <h2>{downloadURL ? "Current release candidate" : "Release candidate incoming"}</h2>
          <p>
            {downloadURL
              ? "Download the exact build linked below, then follow the setup guide for Camera and Accessibility permissions."
              : "The public site is ready. The signed or clearly labeled fallback app archive will appear here when release packaging finishes."}
          </p>
          {downloadURL ? (
            <a className="button button-primary" href={downloadURL}>Download Signal <span>↓</span></a>
          ) : (
            <a className="button button-outline-light" href="/setup">Read setup guide</a>
          )}
          <dl className="release-metadata">
            <div><dt>Version</dt><dd>{version}</dd></div>
            <div><dt>Commit</dt><dd><code>{commit}</code></dd></div>
            <div><dt>SHA-256</dt><dd><code>{checksum}</code></dd></div>
            <div><dt>Architecture</dt><dd>{architecture}</dd></div>
            <div><dt>Signing</dt><dd>{signingStatus}</dd></div>
            <div><dt>Notarization</dt><dd>{notarizationStatus}</dd></div>
          </dl>
          <div className="gatekeeper-note">
            <h3>Gatekeeper</h3>
            {!downloadURL ? (
              <p>No artifact is published yet. Do not use a Gatekeeper workaround until a download and matching SHA-256 are listed.</p>
            ) : isAdHoc ? (
              <p>This build is ad hoc or not notarized. Verify its SHA-256 first, move Signal to Applications, then Control-click Signal and choose Open. If macOS still blocks it, use Privacy &amp; Security → Open Anyway. Do not disable Gatekeeper or run quarantine-removal commands.</p>
            ) : (
              <p>Verify the SHA-256, move Signal to Applications, and open it normally. If macOS presents a publisher prompt, confirm it matches the signing status above.</p>
            )}
          </div>
        </div>
      </div>
      </main>
    </>
  );
}
