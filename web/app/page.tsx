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
          href="/downloads/signal-extension.zip"
          download
        >
          Download extension
          <span aria-hidden="true">↓</span>
        </a>
        <p className={styles.note}>
          Unzip, open <strong>chrome://extensions</strong>, enable Developer
          mode, and choose Load unpacked.
        </p>
      </section>
    </main>
  );
}
