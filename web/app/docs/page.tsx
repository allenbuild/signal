import type { Metadata } from "next";
import Link from "next/link";
import { gestures, touchControls } from "../../lib/product";

export const metadata: Metadata = {
  title: "Docs",
  description: "Signal setup, gesture, planner, profile, and API documentation.",
};

const api = [
  ["GET", "/api/v1/health", "Service readiness without dependency details"],
  ["POST", "/api/v1/plan", "Generate a validated preview or clarification"],
  ["POST", "/api/v1/profiles", "Publish a redacted unlisted profile"],
  ["GET", "/api/v1/profiles/:shareCode", "Read an unlisted profile"],
  ["POST", "/api/v1/integrations/discord", "Send an approved typed Discord action"],
] as const;

export default function DocsPage() {
  return (
    <main id="main-content" className="page-main">
      <section className="page-hero shell">
        <p className="eyebrow">Documentation · Schema v1</p>
        <h1>Build in the browser. Run on the Mac.</h1>
        <p>
          The website builds, previews, and shares commands. The Signal Mac app
          recognizes gestures and performs system-wide actions.
        </p>
      </section>
      <div className="shell docs-layout">
        <aside className="docs-nav" aria-label="Documentation sections">
          <a href="#quick-start">Quick start</a>
          <a href="#modes">Modes</a>
          <a href="#controls">Controls</a>
          <a href="#plans">Plans</a>
          <a href="#sharing">Sharing</a>
          <a href="#api">API</a>
          <a href="#limits">Limits</a>
        </aside>
        <article className="docs-content">
          <section id="quick-start">
            <p className="eyebrow">Quick start</p>
            <h2>From an idea to a reviewed mapping.</h2>
            <ol>
              <li>Choose one of the nine command gestures in the <Link href="/builder">builder</Link>.</li>
              <li>Describe the workflow or add safe actions visually.</li>
              <li>Review every step, warning, timeout, and confirmation rule.</li>
              <li>Save locally, export JSON, or publish a redacted unlisted profile.</li>
              <li>Import into the Mac app and explicitly approve before the first run.</li>
            </ol>
          </section>
          <section id="modes">
            <p className="eyebrow">Modes</p>
            <h2>Touch, Commands, or Hybrid.</h2>
            <p><strong>Touch</strong> keeps pointer controls primary. <strong>Commands</strong> focuses on mapped poses. <strong>Hybrid</strong> combines both and lets the One pose remain pointer control or become a command.</p>
          </section>
          <section id="controls">
            <p className="eyebrow">Gesture vocabulary</p>
            <h2>Four touch controls and nine command poses.</h2>
            <div className="docs-chip-list">
              {touchControls.map((item) => <span key={item.title}>{item.title}</span>)}
              {gestures.map((item) => <span key={item.id}>{item.label}</span>)}
            </div>
          </section>
          <section id="plans">
            <p className="eyebrow">Plans and Teach by Demo</p>
            <h2>Everything is inspectable.</h2>
            <p>
              Natural language and Teach by Demo both produce portable version 1
              plans. They never execute in the planner service. The client
              validates again, previews each effect, and requests the configured
              confirmation before save or first run.
            </p>
          </section>
          <section id="sharing">
            <p className="eyebrow">Profiles and sharing</p>
            <h2>Guest-first and portable.</h2>
            <p>
              Browser drafts stay local. JSON import and export require no
              account. Publishing creates a stable <code>SIG1-XXXXXXXX</code>
              link to redacted, non-secret content. A share code is an unlisted
              read-only identifier—not authentication.
            </p>
          </section>
          <section id="api">
            <p className="eyebrow">HTTP API</p>
            <h2>Native-friendly, no browser login required.</h2>
            <div className="api-table">
              {api.map(([method, path, purpose]) => (
                <div key={path}><code>{method}</code><code>{path}</code><span>{purpose}</span></div>
              ))}
            </div>
            <p>
              Requests and responses use schema version 1. Planner responses are
              either <code>planned</code> or <code>needs_clarification</code>.
              Rejections use typed error codes and include a request ID.
            </p>
          </section>
          <section id="limits">
            <p className="eyebrow">Version 1 limits</p>
            <h2>Bounded by design.</h2>
            <ul>
              <li>50 plan steps; 10 actions per conditional branch</li>
              <li>300 second plan timeout; 60 second step timeout</li>
              <li>30 second wait action; 20 secret references</li>
              <li>9 gesture mappings; schema version 1 only</li>
            </ul>
          </section>
        </article>
      </div>
    </main>
  );
}
