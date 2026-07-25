import { and, eq, isNotNull, isNull, lt, or } from "drizzle-orm";

import { sharedProfiles } from "../db/schema";
import {
  profileSchema,
  type Profile,
} from "./contracts";

const SHARE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const SHARE_CODE_PREFIX = "SIG1-";
const SHARE_CODE_PATTERN =
  /^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/;
const MAX_INSERT_ATTEMPTS = 8;
export const ACTIVE_PROFILE_RETENTION_MS = 365 * 24 * 60 * 60 * 1000;
export const REVOKED_PROFILE_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

type StoredProfile = {
  shareCode: string;
  profileId: string;
  profileJson: string;
  revokeTokenHash: string;
  createdAtMs: number;
  revokedAtMs: number | null;
};

type MemoryState = {
  profiles: Map<string, StoredProfile>;
};

type GlobalProfileState = typeof globalThis & {
  __signalProfileStore?: MemoryState;
};

const globalProfileState = globalThis as GlobalProfileState;
const memoryState =
  globalProfileState.__signalProfileStore ??
  (globalProfileState.__signalProfileStore = { profiles: new Map() });

export type CreatedSharedProfile = {
  profile: Profile;
  shareCode: string;
  revokeToken: string;
};

export class ProfileStoreUnavailableError extends Error {
  constructor(options?: ErrorOptions) {
    super("Persistent profile storage is unavailable.", options);
    this.name = "ProfileStoreUnavailableError";
  }
}

function allowMemoryFallback() {
  return process.env.NODE_ENV !== "production";
}

async function getPersistentDb() {
  if (process.env.NODE_ENV === "test") return null;

  try {
    const { getDbOrNull } = await import("../db");
    const db = getDbOrNull();
    if (db) return db;
  } catch (error) {
    if (!allowMemoryFallback()) {
      throw new ProfileStoreUnavailableError({ cause: error });
    }
    return null;
  }

  if (allowMemoryFallback()) return null;
  throw new ProfileStoreUnavailableError();
}

/**
 * Enforces the data-lifetime boundary whenever the profile service is used.
 * Operators must additionally schedule the documented daily D1 statement so a
 * completely idle database is purged within the policy window.
 */
export async function purgeExpiredSharedProfiles(nowMs = Date.now()) {
  const activeCutoffMs = nowMs - ACTIVE_PROFILE_RETENTION_MS;
  const revokedCutoffMs = nowMs - REVOKED_PROFILE_RETENTION_MS;
  const db = await getPersistentDb();
  if (db) {
    try {
      await db
        .delete(sharedProfiles)
        .where(
          or(
            lt(sharedProfiles.createdAtMs, activeCutoffMs),
            and(
              isNotNull(sharedProfiles.revokedAtMs),
              lt(sharedProfiles.revokedAtMs, revokedCutoffMs),
            ),
          ),
        );
      return;
    } catch (error) {
      throw new ProfileStoreUnavailableError({ cause: error });
    }
  }

  for (const [shareCode, row] of memoryState.profiles) {
    if (
      row.createdAtMs < activeCutoffMs ||
      (row.revokedAtMs !== null && row.revokedAtMs < revokedCutoffMs)
    ) {
      memoryState.profiles.delete(shareCode);
    }
  }
}

function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

export function generateShareCode(): string {
  const bytes = randomBytes(8);
  let payload = "";
  for (const byte of bytes) {
    payload += SHARE_CODE_ALPHABET[byte & 31];
  }
  return `${SHARE_CODE_PREFIX}${payload}`;
}

export function normalizeShareCode(value: string): string | null {
  const normalized = value.trim().toUpperCase();
  return SHARE_CODE_PATTERN.test(normalized) ? normalized : null;
}

function generateRevokeToken(): string {
  const bytes = randomBytes(32);
  let token = "SRV1_";
  for (const byte of bytes) token += byte.toString(16).padStart(2, "0");
  return token;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

/**
 * Re-validating after injecting the server-generated code both canonicalizes
 * the stored JSON and guarantees that only portable v1 fields are returned.
 * Resolution state and secret values are not members of the strict contract.
 */
export function sanitizePublicProfile(
  profile: Profile,
  shareCode: string,
): Profile {
  return profileSchema.parse({
    ...profile,
    share: {
      visibility: "unlisted",
      shareCode,
    },
  });
}

function parseStoredProfile(serialized: string): Profile {
  try {
    return profileSchema.parse(JSON.parse(serialized));
  } catch (error) {
    throw new ProfileStoreUnavailableError({ cause: error });
  }
}

export async function createSharedProfile(
  profile: Profile,
): Promise<CreatedSharedProfile> {
  if (
    profile.share.visibility !== "unlisted" ||
    profile.share.shareCode !== undefined
  ) {
    throw new TypeError(
      "A new share must be unlisted and must not supply its own share code.",
    );
  }

  await purgeExpiredSharedProfiles();
  const revokeToken = generateRevokeToken();
  const revokeTokenHash = await sha256(revokeToken);
  const db = await getPersistentDb();

  for (let attempt = 0; attempt < MAX_INSERT_ATTEMPTS; attempt += 1) {
    const shareCode = generateShareCode();
    const publicProfile = sanitizePublicProfile(profile, shareCode);
    const row: StoredProfile = {
      shareCode,
      profileId: publicProfile.id,
      profileJson: JSON.stringify(publicProfile),
      revokeTokenHash,
      createdAtMs: Date.now(),
      revokedAtMs: null,
    };

    if (db) {
      try {
        const inserted = await db
          .insert(sharedProfiles)
          .values(row)
          .onConflictDoNothing({ target: sharedProfiles.shareCode })
          .returning({ shareCode: sharedProfiles.shareCode });
        if (inserted.length === 1) {
          return { profile: publicProfile, shareCode, revokeToken };
        }
      } catch (error) {
        throw new ProfileStoreUnavailableError({ cause: error });
      }
      continue;
    }

    if (!memoryState.profiles.has(shareCode)) {
      memoryState.profiles.set(shareCode, row);
      return { profile: publicProfile, shareCode, revokeToken };
    }
  }

  throw new ProfileStoreUnavailableError();
}

export async function readSharedProfile(
  shareCode: string,
): Promise<Profile | null> {
  const normalized = normalizeShareCode(shareCode);
  if (!normalized) return null;

  await purgeExpiredSharedProfiles();
  const db = await getPersistentDb();
  if (db) {
    try {
      const [row] = await db
        .select({ profileJson: sharedProfiles.profileJson })
        .from(sharedProfiles)
        .where(
          and(
            eq(sharedProfiles.shareCode, normalized),
            isNull(sharedProfiles.revokedAtMs),
          ),
        )
        .limit(1);
      return row ? parseStoredProfile(row.profileJson) : null;
    } catch (error) {
      throw new ProfileStoreUnavailableError({ cause: error });
    }
  }

  const row = memoryState.profiles.get(normalized);
  return row && row.revokedAtMs === null
    ? parseStoredProfile(row.profileJson)
    : null;
}

export async function revokeSharedProfile(
  shareCode: string,
  revokeToken: string,
): Promise<boolean> {
  const normalized = normalizeShareCode(shareCode);
  if (!normalized || !revokeToken || revokeToken.length > 256) return false;

  await purgeExpiredSharedProfiles();
  const providedHash = await sha256(revokeToken);
  const db = await getPersistentDb();
  if (db) {
    try {
      const [row] = await db
        .select({ revokeTokenHash: sharedProfiles.revokeTokenHash })
        .from(sharedProfiles)
        .where(
          and(
            eq(sharedProfiles.shareCode, normalized),
            isNull(sharedProfiles.revokedAtMs),
          ),
        )
        .limit(1);
      if (
        !row ||
        !constantTimeEqual(row.revokeTokenHash, providedHash)
      ) {
        return false;
      }

      const updated = await db
        .update(sharedProfiles)
        .set({ revokedAtMs: Date.now() })
        .where(
          and(
            eq(sharedProfiles.shareCode, normalized),
            eq(sharedProfiles.revokeTokenHash, providedHash),
            isNull(sharedProfiles.revokedAtMs),
          ),
        )
        .returning({ shareCode: sharedProfiles.shareCode });
      return updated.length === 1;
    } catch (error) {
      throw new ProfileStoreUnavailableError({ cause: error });
    }
  }

  const row = memoryState.profiles.get(normalized);
  if (
    !row ||
    row.revokedAtMs !== null ||
    !constantTimeEqual(row.revokeTokenHash, providedHash)
  ) {
    return false;
  }
  row.revokedAtMs = Date.now();
  memoryState.profiles.set(normalized, row);
  return true;
}

export function resetProfileStoreForTests() {
  memoryState.profiles.clear();
}
