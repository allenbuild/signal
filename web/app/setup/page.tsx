import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Install Signal",
  description:
    "Download and load the Signal Chrome extension for cross-tab hand control.",
};

const steps = [
  ["Download Signal", "Download the Signal extension ZIP."],
  ["Unzip it", "Expand the ZIP to reveal the signal-extension folder."],
  ["Open extensions", "Open chrome://extensions in desktop Chrome."],
  ["Enable Developer Mode", "Turn on Developer mode in the upper-right corner."],
  ["Load unpacked", "Choose Load unpacked."],
  ["Select Signal", "Select the unzipped signal-extension folder."],
  ["Pin Signal", "Pin Signal from Chrome’s Extensions menu."],
  ["Open the side panel", "Open Signal’s side panel from the toolbar."],
  ["Start Signal", "Click Start Signal and grant the one-time camera permission."],
] as const;

export default function SetupPage() {
  return (
    <main className="page-main" id="main-content">
      <section className="page-hero shell">
        <p className="eyebrow">Chrome extension · About two minutes</p>
        <h1>Control the web from one side panel.</h1>
        <p>
          Signal follows you across ordinary Chrome tabs. It needs no native
          companion, Accessibility access, localhost process, account, or cloud
          camera upload.
        </p>
        <div className="button-row">
          <a className="button button-primary" href="/downloads/signal-extension.zip" download>
            Download Signal for Chrome <span aria-hidden="true">↓</span>
          </a>
          <a
            className="button button-secondary"
            href="/downloads/signal-extension.zip.sha256"
            download
          >
            SHA-256 checksum
          </a>
        </div>
        <p className="honesty-line">
          Hackathon distribution uses Chrome’s Load unpacked flow. Signal does
          not claim Chrome Web Store availability or zero-install control.
        </p>
      </section>
      <section className="section shell">
        <ol className="install-steps">
          {steps.map(([title, copy], index) => (
            <li key={title}>
              <span>{String(index + 1).padStart(2, "0")}</span>
              <div>
                <h2>{title}</h2>
                <p>{copy}</p>
              </div>
            </li>
          ))}
        </ol>
        <div className="setup-note">
          <p className="eyebrow">Protected pages</p>
          <p>
            Chrome does not let extensions control chrome:// pages, the Chrome
            Web Store, browser settings, extension management, DevTools, or
            operating-system UI. Signal reports this limitation visibly and
            resumes on the next supported website.
          </p>
        </div>
      </section>
    </main>
  );
}
