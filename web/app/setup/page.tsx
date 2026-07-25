import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Setup",
  description: "Install Signal and grant the narrow macOS permissions it needs.",
};

const steps = [
  [
    "Install and open",
    "Move Signal to Applications, open it, and follow macOS’s first-launch prompt. If Gatekeeper asks, use the release page’s signing-specific instructions.",
  ],
  [
    "Allow Camera",
    "Open System Settings → Privacy & Security → Camera, then enable the exact Signal app you installed. Frames remain in memory on your Mac.",
  ],
  [
    "Allow Accessibility",
    "Open Privacy & Security → Accessibility and enable Signal. If you replace the app, remove the old entry and add the new release.",
  ],
  [
    "Calibrate, then enable",
    "Choose Hybrid mode, confirm the landmark view is stable, and explicitly enable output. Control–Option–Command–H closes the output gate and requests macro cancellation.",
  ],
] as const;

export default function SetupPage() {
  return (
    <main className="page-main" id="main-content">
      <section className="page-hero shell">
        <p className="eyebrow">Setup · About five minutes</p>
        <h1>Give Signal permission to help.</h1>
        <p>
          Signal uses the camera to understand hand landmarks and Accessibility
          to control the real cursor and frontmost app. Output starts paused and
          must be enabled explicitly.
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
