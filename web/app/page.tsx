import Link from "next/link";
import { SignalStudio } from "./components/SignalStudio";

const gestures = [
  ["01", "One"],
  ["02", "Two"],
  ["03", "Three"],
  ["04", "Four"],
  ["05", "Five"],
  ["●", "Fist"],
  ["↑", "Thumbs up"],
  ["↓", "Thumbs down"],
  ["C", "C shape"],
];

export default function Home() {
  return (
    <>
      <nav className="site-nav">
        <Link className="brand" href="/" aria-label="Signal home">
          <span className="brand-mark"><i /><i /><i /></span>
          <span>Signal</span>
        </Link>
        <div className="nav-links" aria-label="Primary navigation">
          <a href="#gestures">Gestures</a>
          <a href="#studio">Build</a>
          <Link href="/setup">Setup</Link>
          <Link href="/p/SIG1-SGNL2626">Demo profile</Link>
        </div>
        <Link className="button button-small button-dark" href="/download">
          Download
        </Link>
      </nav>

      <main id="main-content">
      <section className="hero section-shell">
        <div className="hero-copy">
          <p className="eyebrow"><span className="status-dot" /> Native macOS hand interface</p>
          <h1>Your hand already knows the shortcut.</h1>
          <p className="hero-lede">
            Move, click, scroll, and zoom—then turn nine deliberate gestures into
            repeatable workflows across your Mac.
          </p>
          <div className="hero-actions">
            <Link className="button button-primary" href="/download">Get Signal for macOS <span>↗</span></Link>
            <a className="text-link" href="#studio">Build a gesture <span>↓</span></a>
          </div>
          <div className="hero-note">
            <span className="privacy-seal">◎</span>
            <p><strong>Your camera stays on your Mac.</strong><br />No frames uploaded. No telemetry by default.</p>
          </div>
        </div>

        <div className="hero-console" aria-label="Signal live gesture interface preview">
          <div className="console-bar">
            <span className="console-title"><b /> SIGNAL / LIVE</span>
            <span className="mode-pill">HYBRID</span>
          </div>
          <div className="console-main">
            <div className="gesture-radar">
              <div className="radar-grid" />
              <div className="radar-ring ring-one" />
              <div className="radar-ring ring-two" />
              <div className="gesture-token">↑</div>
              <span className="tracking-chip">HAND 01 · TRACKED</span>
            </div>
            <div className="live-data">
              <p className="data-label">GESTURE</p>
              <h2>Thumbs up</h2>
              <div className="confidence-row"><span>Confidence</span><b>92%</b></div>
              <div className="meter"><i /></div>
              <div className="hold-row">
                <div className="hold-ring"><span>0.6</span><small>SEC</small></div>
                <p><b>Hold steady</b><span>Command armed</span></p>
              </div>
            </div>
          </div>
          <div className="command-receipt">
            <div>
              <span className="receipt-index">01</span>
              <p><b>Start focus mode</b><small>3 actions · review required</small></p>
            </div>
            <span className="armed">ARMED</span>
          </div>
          <div className="console-status">
            <span><i className="green-dot" /> Camera active</span>
            <span>31 FPS</span>
            <span>22 ms</span>
            <span className="paused">OUTPUT PAUSED</span>
          </div>
        </div>
      </section>

      <section className="control-strip" aria-label="Touch controls">
        <div><span>POINT</span><b>Move</b><small>Index pose</small></div>
        <div><span>PINCH</span><b>Click</b><small>Quick release</small></div>
        <div><span>↕</span><b>Scroll</b><small>Vertical pinch</small></div>
        <div><span>↔</span><b>Zoom</b><small>Horizontal pinch</small></div>
      </section>

      <section className="feature-intro section-shell" id="gestures">
        <div>
          <p className="eyebrow">One hand. Two layers.</p>
          <h2>A touch interface and a command palette.</h2>
        </div>
        <p>
          Signal preserves the controls that feel immediate, then adds a
          programmable layer for the work you repeat. Hybrid mode keeps both
          ready without letting a pinch accidentally launch a command.
        </p>
      </section>

      <section className="touch-grid section-shell">
        <article className="feature-card feature-card-wide card-ink">
          <div className="feature-top">
            <span className="number">01 / TOUCH</span>
            <span className="feature-icon">⌁</span>
          </div>
          <div>
            <h3>Control the real Mac cursor.</h3>
            <p>Relative movement, pinch-click, vertical scroll, and horizontal zoom use public macOS APIs after you grant Accessibility access.</p>
          </div>
          <div className="axis-demo">
            <span className="axis-hand">+</span>
            <i className="axis-v" />
            <i className="axis-h" />
            <small className="axis-label-v">SCROLL</small>
            <small className="axis-label-h">ZOOM</small>
          </div>
        </article>
        <article className="feature-card card-lime">
          <div className="feature-top">
            <span className="number">02 / COMMANDS</span>
            <span className="feature-icon">⌘</span>
          </div>
          <div>
            <h3>Make any gesture useful.</h3>
            <p>Describe a workflow, review a controlled demo timeline, or build each step directly.</p>
          </div>
          <div className="mini-timeline">
            <span><b>↑</b> Thumbs up</span>
            <i />
            <span><b>3</b> actions</span>
          </div>
        </article>
      </section>

      <section className="gesture-section section-shell">
        <div className="gesture-heading">
          <p className="eyebrow">Nine fixed command gestures</p>
          <h2>A small vocabulary.<br />An unlimited number of outcomes.</h2>
        </div>
        <div className="gesture-grid">
          {gestures.map(([symbol, name], index) => (
            <div className={index === 6 ? "gesture-card featured" : "gesture-card"} key={name}>
              <span className="gesture-symbol">{symbol}</span>
              <div><b>{name}</b><small>{index === 6 ? "Focus mode" : "Ready to map"}</small></div>
            </div>
          ))}
        </div>
      </section>

      <section className="studio-section" id="studio">
        <div className="section-shell">
          <div className="studio-heading">
          <p className="eyebrow eyebrow-light">Try the local profile builder</p>
            <h2>Say what you want.<br />Review every step.</h2>
            <p>
            The planner returns a versioned action plan—not arbitrary code.
              Nothing runs from this website, and every native action still requires approval.
              Generated share links are a best-effort per-worker prototype; use the seeded
              profile for a durable public demo.
            </p>
          </div>
          <SignalStudio />
        </div>
      </section>

      <section className="mode-section section-shell">
        <div className="mode-copy">
          <p className="eyebrow">Designed to avoid collisions</p>
          <h2>Three modes.<br />One obvious state.</h2>
          <p>Signal makes the active control layer visible and starts with output paused. The emergency shortcut closes the output gate and requests macro cancellation.</p>
          <kbd>⌃⌥⌘ H</kbd><span>Emergency pause</span>
        </div>
        <div className="mode-list">
          <article><span>01</span><div><h3>Touch</h3><p>Pointer and pinch controls only. The safest mode for everyday control.</p></div><b>CURSOR</b></article>
          <article className="mode-active"><span>02</span><div><h3>Hybrid</h3><p>Touch stays on. Eight command gestures remain available.</p></div><b>DEFAULT</b></article>
          <article><span>03</span><div><h3>Commands</h3><p>All nine gestures become deliberate programmable triggers.</p></div><b>MACROS</b></article>
        </div>
      </section>

      <section className="trust-section">
        <div className="section-shell trust-grid">
          <div>
            <p className="eyebrow eyebrow-light">Private by architecture</p>
            <h2>The camera sees you.<br />Only your Mac sees the camera.</h2>
          </div>
          <div className="trust-points">
            <article><span>01</span><h3>Frames stay local</h3><p>Vision processing runs on-device. Signal never sends camera frames to the planning API.</p></article>
            <article><span>02</span><h3>Secrets stay out of profiles</h3><p>Shared workflows contain references, never webhook tokens, passwords, or raw credentials.</p></article>
            <article><span>03</span><h3>Actions stay reviewable</h3><p>AI plans are previews. Generic network actions are disabled; fixed integration routes validate their configured destinations.</p></article>
          </div>
        </div>
      </section>

      <section className="origin-section section-shell" id="prior-work">
        <div>
          <p className="eyebrow">Built honestly</p>
          <h2>HandPilot became Signal.</h2>
        </div>
        <div>
          <p>
            Before Night Hack, the team built a native experiment with camera capture,
            hand tracking, input generation, permissions, and touchless pointer, click,
            scroll, and zoom controls.
          </p>
          <p>
            During the hackathon, we created Signal’s programmable gesture layer:
            nine command poses, validated macros, planning, a controlled reviewable
            demo timeline, best-effort profile-link prototypes, a durable seeded profile,
            a public API, and release packaging.
          </p>
          <Link className="text-link" href="/prior-work">Read the full disclosure <span>↗</span></Link>
        </div>
      </section>

      <section className="final-cta">
        <div className="cta-pulse"><i /><i /><i /></div>
        <p className="eyebrow">A new interface is already in your hands.</p>
        <h2>Point. Pinch. Program.</h2>
        <div>
          <Link className="button button-primary" href="/download">Download Signal <span>↗</span></Link>
          <Link className="button button-outline-light" href="/setup">Read setup guide</Link>
        </div>
      </section>
      </main>

      <footer className="site-footer">
        <Link className="brand brand-light" href="/"><span className="brand-mark"><i /><i /><i /></span><span>Signal</span></Link>
        <p>Hand control for the work you repeat.</p>
        <div><Link href="/setup">Setup</Link><Link href="/privacy">Privacy</Link><Link href="/prior-work">Prior work</Link><a href="/api/v1/health">API</a></div>
      </footer>
    </>
  );
}
