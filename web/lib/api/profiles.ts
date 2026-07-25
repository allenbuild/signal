import type { SignalProfile } from "./types";
import { ProfileSchema } from "./schema";
import { parseSeededPlan } from "./planner";

const MAX_PROFILES = 500;
const SHARE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const profiles = new Map<string, SignalProfile>();

const focus = parseSeededPlan({
  schemaVersion: 1,
  requestId: "seed-focus",
  request: "When I give a thumbs up, open my focus playlist, say Focus mode, and send Demo complete to Discord.",
  targetGesture: "thumbs_up",
  actionCatalog: ["open_url", "speak_text", "discord_webhook"],
});
const replay = parseSeededPlan({
  schemaVersion: 1,
  requestId: "seed-replay",
  request: "Replay my recorded TextEdit workflow.",
  targetGesture: "c_shape",
  actionCatalog: ["open_application", "keyboard_shortcut", "type_text"],
});

if (!focus || focus.status !== "planned" || !replay || replay.status !== "planned") {
  throw new Error("Signal seeded profile could not be initialized.");
}

export const seededProfile: SignalProfile = {
  schemaVersion: 1,
  id: "signal.seeded.web",
  name: "Focus Flow",
  description: "A judge-ready profile pairing focus mode with a taught TextEdit workflow.",
  preferredMode: "hybrid",
  hybridOneBehavior: "pointer",
  mappings: [
    {
      gesture: "thumbs_up",
      enabled: true,
      holdDurationMs: 600,
      cooldownMs: 900,
      activation: "one_shot",
      allowedBundleIdentifiers: [],
      preferredMode: "commands",
      plan: focus.plan,
    },
    {
      gesture: "c_shape",
      enabled: true,
      holdDurationMs: 650,
      cooldownMs: 1_000,
      activation: "one_shot",
      allowedBundleIdentifiers: [],
      preferredMode: "commands",
      plan: replay.plan,
    },
  ],
  share: {
    visibility: "unlisted",
    shareCode: "SIG1-SGNL2626",
  },
};

export function validateProfile(
  value: unknown,
): { ok: true; value: SignalProfile } | { ok: false; fields: string[] } {
  const result = ProfileSchema.safeParse(value);
  return result.success
    ? { ok: true, value: result.data as SignalProfile }
    : {
        ok: false,
        fields: [...new Set(result.error.issues.map((issue) => issue.path.map(String).join(".") || "profile"))],
      };
}

function randomShareCode(): string {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  const payload = Array.from(bytes, (byte) => SHARE_ALPHABET[byte % SHARE_ALPHABET.length]).join("");
  return `SIG1-${payload}`;
}

export function saveProfile(profile: SignalProfile): { shareCode: string; profile: SignalProfile } {
  let shareCode = randomShareCode();
  while (profiles.has(shareCode)) shareCode = randomShareCode();
  if (profiles.size >= MAX_PROFILES) {
    const oldestKey = profiles.keys().next().value;
    if (oldestKey) profiles.delete(oldestKey);
  }
  const published: SignalProfile = structuredClone({
    ...profile,
    share: { visibility: "unlisted", shareCode },
  });
  profiles.set(shareCode, published);
  return { shareCode, profile: structuredClone(published) };
}

export function getProfile(shareCode: string): SignalProfile | null {
  const canonical = shareCode.toUpperCase();
  if (canonical === "SIG1-SGNL2626") return structuredClone(seededProfile);
  const profile = profiles.get(canonical);
  return profile ? structuredClone(profile) : null;
}

export function validShareCode(value: string): boolean {
  return /^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/.test(value.toUpperCase());
}
