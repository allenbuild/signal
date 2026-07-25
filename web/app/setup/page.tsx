import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Setup",
  description: "Start Signal in a desktop browser and allow camera access.",
};

const steps = [
  [
    "Open Signal over HTTPS",
    "Use the public Signal website in a current desktop browser. Nothing needs to be downloaded or installed.",
  ],
  [
    "Start Signal",
    "Choose Control or Commands, then click Start Signal. The page never requests the camera before this explicit action.",
  ],
  [
    "Allow the camera",
    "Approve the browser camera prompt. Video frames and hand landmarks stay in this browser tab and are not uploaded.",
  ],
  [
    "Calibrate, then stop safely",
    "Keep one hand visible in the camera card, verify the landmark overlay, and use Stop Signal whenever you want to close the camera track and reset gesture state.",
  ],
] as const;

export default function SetupPage() {
  return (
    <main className="page-main" id="main-content">
      <section className="page-hero shell">
        <p className="eyebrow">Setup · About one minute</p>
        <h1>Start with one browser permission.</h1>
        <p>
          Signal uses the camera to understand hand landmarks locally. It does
          not need Accessibility access, a native companion, or a localhost
          service.
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
      </section>
    </main>
  );
}
