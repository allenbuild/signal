import Link from "next/link";
import { ContentNav } from "../components/ContentNav";

export default function DownloadPage() {
  return (
    <>
      <ContentNav />
      <main className="content-page" id="main-content">
        <div className="content-wrap">
          <p className="eyebrow">Nothing to install</p>
          <h1>Signal now runs entirely in your browser.</h1>
          <p>
            The core experience needs only this public HTTPS site, a modern
            desktop browser, and a webcam. It does not require a native app,
            browser extension, localhost service, account, or download.
          </p>
          <div className="download-panel">
            <h2>Chrome desktop is the primary target</h2>
            <p>
              Open Signal, click Start Signal, and grant camera permission.
              Live camera frames stay in this browser and are not uploaded.
            </p>
            <Link className="button button-primary" href="/">
              Open Signal <span>↗</span>
            </Link>
          </div>
        </div>
      </main>
    </>
  );
}
