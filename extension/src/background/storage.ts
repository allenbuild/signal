import {
  parseStoredProfile,
  safeParseSignalCommand,
} from "../shared/schema";
import {
  DEFAULT_SETTINGS,
  DEFAULT_TUNING,
  sanitizeSettings,
  sanitizeTuning,
} from "../shared/tuning";
import {
  GESTURE_IDS,
  type CommandPlan,
  type CommandSource,
  type SignalCommand,
  type SignalSettings,
  type StoredProfile,
  type GestureTuning,
} from "../shared/types";

export const EXTENSION_STORAGE_KEY = "signal.extension.state.v2";
export const SYNC_SETTINGS_KEY = "signal.extension.settings.v1";
export const LEGACY_FIST_COMMAND_KEY = "signal.fist-command.v1";
export const EXTENSION_STORAGE_VERSION = 2 as const;

export type StoredExtensionState = {
  storageVersion: 2;
  commands: SignalCommand[];
  profiles: StoredProfile[];
  settings: SignalSettings;
  tuning: GestureTuning;
};

export type StorageAreaLike = {
  get(
    keys?: string | string[] | Record<string, unknown> | null,
  ): Promise<Record<string, unknown>>;
  set(items: Record<string, unknown>): Promise<void>;
  remove?(keys: string | string[]): Promise<void>;
};

export type ExtensionStorageDependencies = {
  local: StorageAreaLike;
  sync?: StorageAreaLike;
};

export const DEFAULT_EXTENSION_STATE: Readonly<StoredExtensionState> =
  Object.freeze({
    storageVersion: EXTENSION_STORAGE_VERSION,
    commands: [],
    profiles: [],
    settings: { ...DEFAULT_SETTINGS },
    tuning: { ...DEFAULT_TUNING },
  });

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

function validCommands(value: unknown) {
  if (!Array.isArray(value)) return [];
  const result: SignalCommand[] = [];
  const gestures = new Set<string>();
  for (const candidate of value) {
    const parsed = safeParseSignalCommand(candidate);
    if (parsed.success && !gestures.has(parsed.data.gesture)) {
      result.push(parsed.data);
      gestures.add(parsed.data.gesture);
    }
  }
  return result;
}

function validProfiles(value: unknown) {
  if (!Array.isArray(value)) return [];
  const result: StoredProfile[] = [];
  const ids = new Set<string>();
  for (const candidate of value) {
    try {
      const profile = parseStoredProfile(candidate);
      if (!ids.has(profile.id)) {
        result.push(profile);
        ids.add(profile.id);
      }
    } catch {
      // Malformed imports are intentionally ignored during a best-effort migration.
    }
  }
  return result;
}

function sourceFromPlan(plan: CommandPlan): CommandSource {
  switch (plan.createdSource) {
    case "natural_language":
      return "natural_language";
    case "demo_recording":
      return "recording";
    default:
      return "preset";
  }
}

function migrateLegacyProfile(
  value: unknown,
  nowIso: string,
): StoredProfile | null {
  if (!isRecord(value) || value.schemaVersion !== 1) return null;
  if (
    typeof value.id !== "string" ||
    typeof value.name !== "string" ||
    typeof value.description !== "string" ||
    !Array.isArray(value.mappings)
  ) {
    return null;
  }

  const commands: SignalCommand[] = [];
  for (const mappingValue of value.mappings) {
    if (!isRecord(mappingValue) || !isRecord(mappingValue.plan)) continue;
    if (
      !GESTURE_IDS.includes(
        mappingValue.gesture as (typeof GESTURE_IDS)[number],
      )
    ) {
      continue;
    }
    const plan = mappingValue.plan as unknown as CommandPlan;
    const candidate: SignalCommand = {
      schemaVersion: 1,
      id: `signal.migrated.${mappingValue.gesture}`,
      gesture: mappingValue.gesture as SignalCommand["gesture"],
      name:
        typeof plan.name === "string"
          ? plan.name
          : `${mappingValue.gesture} command`,
      description:
        typeof plan.description === "string" ? plan.description : "",
      source: sourceFromPlan(plan),
      plan,
      createdAt: nowIso,
      updatedAt: nowIso,
      enabled: mappingValue.enabled !== false,
    };
    const parsed = safeParseSignalCommand(candidate);
    if (parsed.success) commands.push(parsed.data);
  }

  try {
    return parseStoredProfile({
      schemaVersion: 1,
      id: value.id,
      name: value.name,
      description: value.description,
      commands,
    });
  } catch {
    return null;
  }
}

function legacyFistCommand(value: unknown) {
  let parsedValue = value;
  if (typeof parsedValue === "string") {
    try {
      parsedValue = JSON.parse(parsedValue);
    } catch {
      return null;
    }
  }
  if (!isRecord(parsedValue) || parsedValue.storageVersion !== 1) return null;
  const parsed = safeParseSignalCommand(parsedValue.command);
  return parsed.success && parsed.data.gesture === "fist" ? parsed.data : null;
}

export function migrateStorageSnapshot(
  snapshot: Record<string, unknown>,
  nowIso = new Date().toISOString(),
): StoredExtensionState {
  const raw = snapshot[EXTENSION_STORAGE_KEY];
  const source = isRecord(raw) ? raw : snapshot;
  const commands = validCommands(source.commands);
  const profiles = validProfiles(source.profiles);

  const legacyProfileInputs = [
    source.profile,
    ...(Array.isArray(source.legacyProfiles) ? source.legacyProfiles : []),
  ];
  for (const input of legacyProfileInputs) {
    const migrated = migrateLegacyProfile(input, nowIso);
    if (
      migrated &&
      !profiles.some((profile) => profile.id === migrated.id)
    ) {
      profiles.push(migrated);
    }
  }

  const fist =
    legacyFistCommand(snapshot[LEGACY_FIST_COMMAND_KEY]) ??
    legacyFistCommand(source[LEGACY_FIST_COMMAND_KEY]);
  if (fist && !commands.some((command) => command.gesture === "fist")) {
    commands.push(fist);
  }

  return {
    storageVersion: EXTENSION_STORAGE_VERSION,
    commands,
    profiles,
    settings: sanitizeSettings(
      isRecord(source.settings)
        ? (source.settings as Partial<SignalSettings>)
        : undefined,
    ),
    tuning: sanitizeTuning(
      isRecord(source.tuning)
        ? (source.tuning as Partial<GestureTuning>)
        : undefined,
    ),
  };
}

export class ExtensionStorage {
  constructor(private readonly dependencies: ExtensionStorageDependencies) {}

  async load(): Promise<StoredExtensionState> {
    const localSnapshot = await this.dependencies.local.get([
      EXTENSION_STORAGE_KEY,
      LEGACY_FIST_COMMAND_KEY,
      "commands",
      "profiles",
      "profile",
      "legacyProfiles",
      "settings",
      "tuning",
    ]);
    const migrated = migrateStorageSnapshot(localSnapshot);

    if (this.dependencies.sync && migrated.settings.useSyncSettings) {
      try {
        const synced = await this.dependencies.sync.get(SYNC_SETTINGS_KEY);
        const syncSettings = synced[SYNC_SETTINGS_KEY];
        if (isRecord(syncSettings)) {
          migrated.settings = sanitizeSettings({
            ...migrated.settings,
            ...(syncSettings as Partial<SignalSettings>),
          });
        }
      } catch {
        // Local storage remains authoritative when sync is unavailable or full.
      }
    }

    await this.save(migrated);
    return migrated;
  }

  async save(state: StoredExtensionState) {
    const sanitized: StoredExtensionState = {
      storageVersion: EXTENSION_STORAGE_VERSION,
      commands: validCommands(state.commands),
      profiles: validProfiles(state.profiles),
      settings: sanitizeSettings(state.settings),
      tuning: sanitizeTuning(state.tuning),
    };
    await this.dependencies.local.set({ [EXTENSION_STORAGE_KEY]: sanitized });
    if (this.dependencies.sync && sanitized.settings.useSyncSettings) {
      try {
        await this.dependencies.sync.set({
          [SYNC_SETTINGS_KEY]: sanitized.settings,
        });
      } catch {
        // Quota or policy failures must not break the fully local product.
      }
    }
  }

  async saveCommand(command: SignalCommand) {
    const parsed = safeParseSignalCommand(command);
    if (!parsed.success) throw parsed.error;
    const state = await this.load();
    state.commands = state.commands.filter(
      (item) =>
        item.id !== parsed.data.id && item.gesture !== parsed.data.gesture,
    );
    state.commands.push(parsed.data);
    await this.save(state);
    return parsed.data;
  }

  async importProfile(value: unknown) {
    const profile = parseStoredProfile(value);
    const state = await this.load();
    state.profiles = state.profiles.filter((item) => item.id !== profile.id);
    state.profiles.push(profile);
    await this.save(state);
    return profile;
  }

  async exportProfile(id: string) {
    const state = await this.load();
    const profile = state.profiles.find((item) => item.id === id);
    if (!profile) throw new Error(`Profile "${id}" was not found.`);
    return JSON.stringify(profile, null, 2);
  }
}
