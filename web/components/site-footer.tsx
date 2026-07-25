import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="shell footer-grid">
        <div>
          <Link className="brand brand-light" href="/">
            <span className="brand-mark" aria-hidden="true">S</span>
            <span>Signal</span>
          </Link>
          <p>Your hand, now programmable.</p>
        </div>
        <div className="footer-links">
          <Link href="/builder">Builder</Link>
          <Link href="/demo">Demo</Link>
          <Link href="/docs">Docs</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/security">Security</Link>
        </div>
        <p className="footer-note">
          Camera frames stay in your browser tab. Plans remain previews until
          you review and approve browser-safe actions.
        </p>
      </div>
    </footer>
  );
}
