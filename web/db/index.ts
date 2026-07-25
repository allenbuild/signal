import { env } from "cloudflare:workers";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import { drizzle } from "drizzle-orm/d1";
import * as schema from "./schema";

export type SignalDatabase = DrizzleD1Database<typeof schema>;

export function getDbOrNull(): SignalDatabase | null {
  if (!env.DB) {
    return null;
  }

  return drizzle(env.DB, { schema });
}

export function getDb(): SignalDatabase {
  const db = getDbOrNull();
  if (!db) {
    throw new Error(
      "Cloudflare D1 binding `DB` is unavailable. Bind D1 as `DB` before using persistent profile storage.",
    );
  }

  return db;
}
