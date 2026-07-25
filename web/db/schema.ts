import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

/**
 * Public shares are deliberately separate from any future private profile
 * storage. The JSON column contains an already-sanitized v1 profile; it must
 * never contain a raw credential or the revoke token.
 */
export const sharedProfiles = sqliteTable(
  "shared_profiles",
  {
    shareCode: text("share_code").primaryKey(),
    profileId: text("profile_id").notNull(),
    profileJson: text("profile_json").notNull(),
    revokeTokenHash: text("revoke_token_hash").notNull(),
    createdAtMs: integer("created_at_ms").notNull(),
    revokedAtMs: integer("revoked_at_ms"),
  },
  (table) => [
    index("shared_profiles_profile_id_idx").on(table.profileId),
    index("shared_profiles_revoked_at_idx").on(table.revokedAtMs),
  ],
);
