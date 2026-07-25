import { ContentNav } from "../components/ContentNav";

export const dynamic = "force-dynamic";

export default function DownloadPage() {
  const downloadURL = process.env.SIGNAL_DOWNLOAD_URL;
  return (
    <main className="content-page">
      <ContentNav />
      <div className="content-wrap">
        <p className="eyebrow">Signal for macOS</p>
        <h1>Put your hand to work.</h1>
        <p>
          Signal is a native macOS app using Apple Vision and public input APIs.
          It does not need a localhost server. macOS 13 or later is recommended.
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
        </div>
      </div>
    </main>
  );
}
