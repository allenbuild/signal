import Link from "next/link";

export function ContentNav() {
  return (
    <nav className="site-nav content-nav">
      <Link className="brand" href="/" aria-label="Signal home">
        <span className="brand-mark"><i /><i /><i /></span><span>Signal</span>
      </Link>
      <div className="nav-links">
        <Link href="/setup">Setup</Link>
        <Link href="/privacy">Privacy</Link>
        <Link href="/prior-work">Prior work</Link>
      </div>
      <Link className="button button-small button-dark" href="/download">Download</Link>
    </nav>
  );
}
