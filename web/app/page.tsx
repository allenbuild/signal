import type { Metadata } from "next";

import styles from "./download-page.module.css";

export const metadata: Metadata = {
  title: "Download Signal",
  description: "Download the Signal hand-control extension for Chrome.",
};

export default function Home() {
  return (
    <main className={styles.page} id="main-content">
      <section className={styles.card} aria-labelledby="download-title">
        <div className={styles.mark} aria-hidden="true">S</div>
        <p className={styles.eyebrow}>Signal for Chrome</p>
        <h1 id="download-title">signal</h1>
        <p className={styles.summary}>
          Hand control and one-shot gesture commands across browser tabs.
        </p>
        <a
          className={styles.download}
          href="/downloads/signal-extension.zip?v=0.3.1"
          download
        >
          Download extension
          <span aria-hidden="true">↓</span>
        </a>
        <section className={styles.instructions} aria-labelledby="install-title">
          <p className={styles.instructionsEyebrow}>Install in Chrome</p>
          <h2 id="install-title">Four quick steps</h2>
          <ol className={styles.steps}>
            <li>
              <span className={styles.stepNumber}>1</span>
              <div>
                <strong>Unzip the download</strong>
                <p>
                  Open Downloads and double-click{" "}
                  <code>signal-extension.zip</code>. Keep the unzipped{" "}
                  <code>signal-extension</code> folder.
                </p>
              </div>
            </li>
            <li>
              <span className={styles.stepNumber}>2</span>
              <div>
                <strong>Open Chrome Extensions</strong>
                <p>
                  Type <code>chrome://extensions</code> into Chrome&apos;s
                  address bar and press Return.
                </p>
              </div>
            </li>
            <li>
              <span className={styles.stepNumber}>3</span>
              <div>
                <strong>Turn on Developer mode</strong>
                <p>Use the switch in the upper-right corner of the page.</p>
              </div>
            </li>
            <li>
              <span className={styles.stepNumber}>4</span>
              <div>
                <strong>Add Signal</strong>
                <p>
                  Drag the unzipped folder onto the Extensions page. If Chrome
                  does not accept the drag, choose <b>Load unpacked</b> and
                  select that folder.
                </p>
              </div>
            </li>
          </ol>
        </section>
        <p className={styles.note}>
          Pin Signal from Chrome&apos;s puzzle-piece menu, then open it on a
          normal website tab. Chrome blocks page control on{" "}
          <strong>chrome://</strong> pages.
        </p>
      </section>
    </main>
  );
}
