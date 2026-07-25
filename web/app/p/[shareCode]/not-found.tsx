import Link from "next/link";

export default function SharedProfileNotFound() {
  return (
    <main id="main-content" className="page-main">
      <section className="page-hero shell">
        <p className="eyebrow">Unlisted Signal profile</p>
        <h1>This profile is unavailable.</h1>
        <p>
          The link may be invalid, private, or no longer shared. Signal uses the
          same response for every unavailable profile.
        </p>
        <div className="button-row">
          <Link className="button button-primary" href="/builder">
            Open Builder
          </Link>
          <Link className="button button-secondary" href="/">
            Return home
          </Link>
        </div>
      </section>
    </main>
  );
}
