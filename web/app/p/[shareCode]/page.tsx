import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { PublicProfileActions } from "../../../components/public-profile-actions";
import { gestures } from "../../../lib/product";
import {
  ProfileStoreUnavailableError,
  readSharedProfile,
} from "../../../lib/profile-store";

type PageProps = {
  params: Promise<{ shareCode: string }> | { shareCode: string };
};

export const metadata: Metadata = {
  title: "Shared profile",
  description: "Review and import a redacted, unlisted Signal gesture profile.",
  robots: { index: false, follow: false },
};

function actionSummary(action: { type: string; parameters: Record<string, unknown> }) {
  switch (action.type) {
    case "open_application":
      return "Unavailable legacy native action";
    case "open_url":
      return `Open ${String(action.parameters.url ?? "a public HTTPS URL")}`;
    case "open_deep_link":
      return "Unavailable legacy deep-link action";
    case "speak_text":
      return `Say “${String(action.parameters.text ?? "")}”`;
    case "show_notification":
      return `Show “${String(action.parameters.title ?? "notification")}”`;
    case "wait":
      return `Wait ${Number(action.parameters.durationMs ?? 0) / 1000} seconds`;
    case "discord_webhook":
      return `Send “${String(action.parameters.message ?? "")}” using your Discord connection`;
    case "slack_webhook":
      return "Unavailable legacy integration action";
    default:
      return action.type.replaceAll("_", " ");
  }
}

export default async function PublicProfilePage({ params }: PageProps) {
  const { shareCode } = await params;
  let profile;
  try {
    profile = await readSharedProfile(shareCode);
  } catch (error) {
    if (error instanceof ProfileStoreUnavailableError) notFound();
    throw error;
  }
  if (!profile) notFound();

  const mappingByGesture = new Map(
    profile.mappings.map((mapping) => [mapping.gesture, mapping]),
  );
  const canonicalCode = profile.share.shareCode ?? shareCode.toUpperCase();

  return (
    <main id="main-content" className="page-main">
      <section className="page-hero shell public-profile-hero">
        <div>
          <p className="eyebrow">Unlisted Signal profile · Schema v1</p>
          <h1>{profile.name}</h1>
          <p>{profile.description || "No profile description."}</p>
        </div>
        <div className="public-profile-meta">
          <span>{profile.preferredMode} mode</span>
          <span>{profile.mappings.length} of 9 gestures assigned</span>
          <code>{canonicalCode}</code>
        </div>
      </section>

      <section className="shell public-profile-notice">
        <strong>Read-only and redacted</strong>
        <p>
          Anyone with this link can view the profile. Importing does not run it;
          Signal validates and reviews every step first. Connections use your
          own secret values.
        </p>
      </section>

      <section className="section shell">
        <div className="section-heading split-heading">
          <div>
            <p className="eyebrow">Gesture mappings</p>
            <h2>Review every assigned plan.</h2>
          </div>
          <PublicProfileActions shareCode={canonicalCode} />
        </div>
        <div className="public-gesture-grid">
          {gestures.map((gesture) => {
            const mapping = mappingByGesture.get(gesture.id);
            return (
              <article
                className={`public-gesture-card ${mapping ? "assigned" : ""}`}
                key={gesture.id}
              >
                <div className="public-gesture-heading">
                  <span aria-hidden="true">{gesture.glyph}</span>
                  <div>
                    <p>{gesture.label}</p>
                    <small>{mapping ? `${mapping.plan.steps.length} steps` : "Unassigned"}</small>
                  </div>
                </div>
                {mapping ? (
                  <>
                    <h3>{mapping.plan.name}</h3>
                    <ol>
                      {mapping.plan.steps.map((step, index) => (
                        <li key={step.id}>
                          <span>{String(index + 1).padStart(2, "0")}</span>
                          <p>{actionSummary(step.action)}</p>
                        </li>
                      ))}
                    </ol>
                    <p className="public-plan-rule">
                      {mapping.activation.replaceAll("_", " ")} · Hold {mapping.holdDurationMs} ms ·{" "}
                      {mapping.plan.confirmation.mode.replaceAll("_", " ")} confirmation
                    </p>
                  </>
                ) : (
                  <p className="public-empty">No command is assigned to this gesture.</p>
                )}
              </article>
            );
          })}
        </div>
      </section>
    </main>
  );
}
