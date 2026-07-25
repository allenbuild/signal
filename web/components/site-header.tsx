import Link from "next/link";

const links = [
  ["/builder", "Builder"],
  ["/demo", "Demo"],
  ["/download", "Download"],
  ["/docs", "Docs"],
] as const;

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="shell nav-shell">
        <Link className="brand" href="/" aria-label="Signal home">
          <span className="brand-mark" aria-hidden="true">S</span>
          <span>Signal</span>
        </Link>
        <nav aria-label="Main navigation">
          {links.map(([href, label]) => (
            <Link href={href} key={href}>{label}</Link>
          ))}
        </nav>
        <Link className="nav-cta" href="/builder">
          Open builder <span aria-hidden="true">↗</span>
        </Link>
      </div>
    </header>
  );
}
