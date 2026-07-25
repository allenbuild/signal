import {
  BROWSER_COMMAND_STORAGE_VERSION,
  BrowserCommandSchema,
  type BrowserCommand,
} from "./schema";

export const BROWSER_COMMAND_STORAGE_KEY = "signal.browser-commands";

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface BrowserCommandStore {
  storageVersion: 2;
  commands: BrowserCommand[];
  updatedAt: string;
}

type Clock = () => Date;

function emptyStore(clock: Clock): BrowserCommandStore {
  return {
    storageVersion: BROWSER_COMMAND_STORAGE_VERSION,
    commands: [],
    updatedAt: clock().toISOString(),
  };
}

function safeCommands(value: unknown): BrowserCommand[] {
  if (!Array.isArray(value)) return [];
  const commands: BrowserCommand[] = [];
  for (const candidate of value) {
    const checked = BrowserCommandSchema.safeParse(candidate);
    if (checked.success) commands.push(checked.data);
  }
  return commands;
}

function migrateLegacyCommand(candidate: unknown): BrowserCommand | null {
  const direct = BrowserCommandSchema.safeParse(candidate);
  if (direct.success) return direct.data;
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    return null;
  }
  const legacy = candidate as Record<string, unknown>;
  const legacyAction = legacy.action;
  if (
    !legacyAction ||
    typeof legacyAction !== "object" ||
    Array.isArray(legacyAction)
  ) {
    return null;
  }
  const action = legacyAction as Record<string, unknown>;
  const migratedAction =
    action.type === "openUrl" && typeof action.url === "string"
      ? {
          type: "open_url" as const,
          url: action.url,
          target: "prepared_action_tab" as const,
          fallback: "explicit_same_tab_confirmation" as const,
        }
      : action.type === "speak" && typeof action.text === "string"
        ? { type: "speak_text" as const, text: action.text }
        : null;
  if (!migratedAction) return null;
  const migrated = BrowserCommandSchema.safeParse({
    schemaVersion: 1,
    id: typeof legacy.id === "string" ? legacy.id : "signal.fist.migrated",
    name: typeof legacy.name === "string" ? legacy.name : "Migrated fist command",
    description:
      typeof legacy.description === "string"
        ? legacy.description
        : "Migrated from Signal browser-command storage version 1.",
    gesture: "fist",
    steps: [{ id: "step-1", action: migratedAction, onFailure: "stop" }],
    createdSource: "import",
  });
  return migrated.success ? migrated.data : null;
}

export function migrateBrowserCommandStore(
  value: unknown,
  clock: Clock = () => new Date(),
): BrowserCommandStore {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return emptyStore(clock);
  }
  const record = value as Record<string, unknown>;
  if (record.storageVersion === BROWSER_COMMAND_STORAGE_VERSION) {
    return {
      storageVersion: BROWSER_COMMAND_STORAGE_VERSION,
      commands: safeCommands(record.commands),
      updatedAt:
        typeof record.updatedAt === "string"
          ? record.updatedAt
          : clock().toISOString(),
    };
  }

  if (record.storageVersion === 1 || record.version === 1) {
    const candidates = Array.isArray(record.commands)
      ? record.commands
      : record.customCommand
        ? [record.customCommand]
        : record.command
          ? [record.command]
          : [];
    const commands = candidates
      .map(migrateLegacyCommand)
      .filter((command): command is BrowserCommand => command !== null);
    return {
      storageVersion: BROWSER_COMMAND_STORAGE_VERSION,
      commands,
      updatedAt: clock().toISOString(),
    };
  }
  return emptyStore(clock);
}

function browserStorage(): StorageLike | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

export class BrowserCommandRepository {
  constructor(
    private readonly storage: StorageLike | null = browserStorage(),
    private readonly clock: Clock = () => new Date(),
  ) {}

  load(): BrowserCommandStore {
    if (!this.storage) return emptyStore(this.clock);
    try {
      const raw = this.storage.getItem(BROWSER_COMMAND_STORAGE_KEY);
      if (!raw) return emptyStore(this.clock);
      const migrated = migrateBrowserCommandStore(JSON.parse(raw), this.clock);
      this.persist(migrated);
      return migrated;
    } catch {
      return emptyStore(this.clock);
    }
  }

  list(): BrowserCommand[] {
    return this.load().commands;
  }

  find(id: string): BrowserCommand | null {
    return this.list().find((command) => command.id === id) ?? null;
  }

  save(value: unknown): BrowserCommand {
    const checked = BrowserCommandSchema.safeParse(value);
    if (!checked.success) {
      throw new Error("Cannot save an invalid Signal browser command.");
    }
    const store = this.load();
    const index = store.commands.findIndex(
      (command) => command.id === checked.data.id,
    );
    if (index >= 0) store.commands[index] = checked.data;
    else store.commands.push(checked.data);
    store.updatedAt = this.clock().toISOString();
    this.persist(store);
    return checked.data;
  }

  remove(id: string): boolean {
    const store = this.load();
    const commands = store.commands.filter((command) => command.id !== id);
    if (commands.length === store.commands.length) return false;
    this.persist({
      ...store,
      commands,
      updatedAt: this.clock().toISOString(),
    });
    return true;
  }

  reset(): BrowserCommandStore {
    const store = emptyStore(this.clock);
    if (this.storage) {
      try {
        this.storage.removeItem(BROWSER_COMMAND_STORAGE_KEY);
      } catch {
        // Storage can be denied while the in-memory application remains usable.
      }
    }
    return store;
  }

  exportJson(): string {
    return JSON.stringify(this.load(), null, 2);
  }

  importJson(raw: string): BrowserCommandStore {
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error("Command import is not valid JSON.");
    }
    const migrated = migrateBrowserCommandStore(parsed, this.clock);
    const originalCount =
      parsed &&
      typeof parsed === "object" &&
      !Array.isArray(parsed) &&
      Array.isArray((parsed as Record<string, unknown>).commands)
        ? ((parsed as Record<string, unknown>).commands as unknown[]).length
        : null;
    if (
      originalCount !== null &&
      originalCount > 0 &&
      migrated.commands.length !== originalCount
    ) {
      throw new Error("Command import contains invalid or unsafe commands.");
    }
    this.persist(migrated);
    return migrated;
  }

  private persist(store: BrowserCommandStore): void {
    if (!this.storage) return;
    try {
      this.storage.setItem(BROWSER_COMMAND_STORAGE_KEY, JSON.stringify(store));
    } catch {
      // Storage may be unavailable in privacy modes; commands remain usable in memory.
    }
  }
}
