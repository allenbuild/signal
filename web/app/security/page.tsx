import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Security",
  description: "Signal’s plan validation, confirmation, sharing, and network safeguards.",
};

const safeguards = [
  ["Paused by default", "Output gates remain closed until you explicitly enable them. Emergency stop cancels active output."],
  ["Allowlisted plans", "Schema version 1 accepts a bounded action union—no shell commands, raw AppleScript, or arbitrary authorization headers."],
  ["Review before run", "Generated plans are previews. Every effect, timeout, failure policy, and confirmation rule is visible before saving."],
  ["Secret references", "Portable profiles identify connections but never contain the corresponding token, password, cookie, or webhook URL."],
  ["Public HTTPS only", "Network actions reject local and private destinations and must re-check resolved addresses and redirects at execution."],
  ["Bounded execution", "Plans, conditional branches, waits, timeouts, request sizes, responses, and integration messages have explicit limits."],
] as const;

export default function SecurityPage() {
  return (
    <main id="main-content" className="page-main">
      <section className="page-hero shell">
        <p className="eyebrow">Security</p>
        <h1>Plans are data to review—not permission to run.</h1>
        <p>
          Signal treats natural-language output, imported profiles, and public
          shares as untrusted until strict validation and explicit approval.
        </p>
      </section>
      <section className="shell safeguard-grid">
        {safeguards.map(([title, copy], index) => (
          <article key={title}>
            <span className="card-index">0{index + 1}</span>
            <h2>{title}</h2>
            <p>{copy}</p>
          </article>
        ))}
      </section>
      <section className="section shell">
        <div className="security-callout">
          <div>
            <p className="eyebrow">Unlisted is not private</p>
            <h2>Share codes grant read-only access.</h2>
          </div>
          <p>
            Anyone with a share link can view its redacted profile. Codes do not
            authorize editing, revocation, secret retrieval, or integration
            execution. Sensitive profiles should remain private.
          </p>
        </div>
      </section>
    </main>
  );
}
