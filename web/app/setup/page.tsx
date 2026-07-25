import { ContentNav } from "../components/ContentNav";

export default function SetupPage() {
  return (
    <main className="content-page">
      <ContentNav />
      <div className="content-wrap">
        <p className="eyebrow">Setup / about five minutes</p>
        <h1>Give Signal permission to help.</h1>
        <p>
          Signal uses the camera to understand hand landmarks and Accessibility
          to control the real cursor and frontmost app. You stay in control:
          output starts paused and must be enabled explicitly.
        </p>
        <div className="content-grid">
          <article className="content-card"><span>01</span><h2>Install and open</h2><p>Move Signal to Applications, open it, and follow macOS’s first-launch prompt. If Gatekeeper asks, use the release page’s signing-specific instructions.</p></article>
          <article className="content-card"><span>02</span><h2>Allow Camera</h2><p>Open System Settings → Privacy &amp; Security → Camera, then enable the exact Signal app you installed. Frames remain in memory on your Mac.</p></article>
          <article className="content-card"><span>03</span><h2>Allow Accessibility</h2><p>Open Privacy &amp; Security → Accessibility and enable Signal. If you replace the app, remove the old entry and add the new release candidate.</p></article>
          <article className="content-card"><span>04</span><h2>Calibrate, then enable</h2><p>Choose Hybrid mode, confirm the landmark view is stable, and explicitly enable output. Use Control–Option–Command–H for an immediate emergency pause.</p></article>
        </div>
      </div>
    </main>
  );
}
