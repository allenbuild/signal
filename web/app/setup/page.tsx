import Link from "next/link";
import { ContentNav } from "../components/ContentNav";

export default function SetupPage() {
  return (
    <>
      <ContentNav />
      <main className="content-page" id="main-content">
        <div className="content-wrap">
          <p className="eyebrow">Browser setup / under one minute</p>
          <h1>One click starts local hand tracking.</h1>
          <p>
            Signal controls its own web interface and browser-safe workflows.
            It does not synthesize operating-system-wide input or control
            arbitrary desktop applications.
          </p>
          <div className="content-grid">
            <article className="content-card"><span>01</span><h2>Use a desktop browser</h2><p>Current Chrome on macOS, Windows, or Linux is the primary supported path. No account or installation is required.</p></article>
            <article className="content-card"><span>02</span><h2>Click Start Signal</h2><p>This real click requests camera permission, prepares local MediaPipe tracking, and attempts to open one reusable action tab.</p></article>
            <article className="content-card"><span>03</span><h2>Allow Camera</h2><p>The mirrored preview and hand landmarks appear after permission. Frames are processed locally and are not uploaded or stored.</p></article>
            <article className="content-card"><span>04</span><h2>Choose a mode</h2><p>Control moves Signal’s virtual cursor and handles pinch actions. Commands recognizes deliberate held poses. Press Escape at any time to pause.</p></article>
          </div>
          <Link className="button button-primary" href="/">Start on the Signal page <span>↗</span></Link>
        </div>
      </main>
    </>
  );
}
