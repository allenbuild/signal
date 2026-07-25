import {
  GESTURE_IDS,
  type BrowserCommandAction,
  type CommandPlan,
  type CommandStep,
  type SignalCommand,
  type StoredProfile,
} from "./types";

const IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const SECRET_MATERIAL = [
  /\bbearer\s+[A-Za-z0-9._~+/=-]{16,}\b/i,
  /\b(?:sk|pk|api)[-_][A-Za-z0-9_-]{16,}\b/i,
  /\bgh[pousr]_[A-Za-z0-9]{20,}\b/i,
  /\bxox[baprs]-[A-Za-z0-9-]{16,}\b/i,
  /\bAIza[0-9A-Za-z_-]{20,}\b/,
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
] as const;
const SENSITIVE_SELECTOR =
  /password|passwd|passcode|credential|one.?time.?code|auth.?token|secret/i;

type ValidationResult<T> =
  | { success: true; data: T }
  | { success: false; error: Error };

function fail(path: string, message: string): never {
  throw new TypeError(`${path}: ${message}`);
}

function record(value: unknown, path: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(path, "expected an object");
  }
  return value as Record<string, unknown>;
}

function exactKeys(
  value: Record<string, unknown>,
  allowed: readonly string[],
  path: string,
) {
  const unexpected = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unexpected.length) {
    fail(path, `unknown field "${unexpected[0]}"`);
  }
}

function string(
  value: unknown,
  path: string,
  minLength: number,
  maxLength: number,
) {
  if (
    typeof value !== "string" ||
    value.length < minLength ||
    value.length > maxLength
  ) {
    fail(path, `expected a string between ${minLength} and ${maxLength} characters`);
  }
  return value;
}

function number(
  value: unknown,
  path: string,
  min: number,
  max: number,
  integer = false,
) {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < min ||
    value > max ||
    (integer && !Number.isInteger(value))
  ) {
    fail(path, `expected a ${integer ? "whole " : ""}number from ${min} to ${max}`);
  }
  return value;
}

function identifier(value: unknown, path: string) {
  const parsed = string(value, path, 1, 64);
  if (!IDENTIFIER.test(parsed)) fail(path, "invalid identifier");
  return parsed;
}

function noSecretMaterial(value: string, path: string) {
  if (SECRET_MATERIAL.some((pattern) => pattern.test(value))) {
    fail(path, "inline secret material is not allowed");
  }
}

export function isSafeWebUrl(value: string) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return false;
    if (url.username || url.password) return false;
    const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
    if (
      host === "localhost" ||
      host === "::1" ||
      host === "0.0.0.0" ||
      host.endsWith(".localhost") ||
      host.endsWith(".local")
    ) {
      return false;
    }
    if (
      /^(\d{1,3}\.){3}\d{1,3}$/.test(host) ||
      host.includes(":") ||
      !host.includes(".") ||
      host.endsWith(".internal") ||
      host.endsWith(".home") ||
      host.endsWith(".lan")
    ) {
      return false;
    }
    return Boolean(host);
  } catch {
    return false;
  }
}

function safeUrl(value: unknown, path: string) {
  const parsed = string(value, path, 8, 2_048);
  if (!isSafeWebUrl(parsed)) {
    fail(path, "only public HTTPS hostname URLs without credentials are allowed");
  }
  return parsed;
}

function safeSelector(value: unknown, path: string) {
  const parsed = string(value, path, 1, 512);
  if (SENSITIVE_SELECTOR.test(parsed)) {
    fail(path, "selectors targeting sensitive fields are not allowed");
  }
  return parsed;
}

function safeOrigin(value: unknown, path: string) {
  const parsed = string(value, path, 8, 2_048);
  let url: URL;
  try {
    url = new URL(parsed);
  } catch {
    fail(path, "expected an ordinary HTTP or HTTPS origin");
  }
  if (
    !["http:", "https:"].includes(url.protocol) ||
    url.origin !== parsed ||
    !url.hostname
  ) {
    fail(path, "expected an ordinary HTTP or HTTPS origin");
  }
  return parsed;
}

function confirmation(value: unknown, path: string) {
  const item = record(value, path);
  exactKeys(item, ["mode", "reason"], path);
  if (!["none", "first_run", "every_run"].includes(String(item.mode))) {
    fail(`${path}.mode`, "invalid confirmation mode");
  }
  string(item.reason, `${path}.reason`, 0, 160);
}

function failurePolicy(value: unknown, path: string) {
  if (!["stop", "continue", "ask"].includes(String(value))) {
    fail(path, "invalid failure policy");
  }
}

function params(
  value: Record<string, unknown>,
  allowed: readonly string[],
  required: readonly string[],
  path: string,
) {
  exactKeys(value, allowed, path);
  for (const key of required) {
    if (!(key in value)) fail(`${path}.${key}`, "required field is missing");
  }
}

function parseAction(value: unknown, path: string): BrowserCommandAction {
  const item = record(value, path);
  exactKeys(item, ["type", "parameters"], path);
  if (typeof item.type !== "string") fail(`${path}.type`, "expected a string");
  const p = record(item.parameters, `${path}.parameters`);
  const pp = `${path}.parameters`;
  switch (item.type) {
    case "open_url":
      params(p, ["url", "networkPolicy", "disposition"], ["url"], pp);
      safeUrl(p.url, `${pp}.url`);
      if (
        p.networkPolicy !== undefined &&
        !["public_web_only", "public_https_only"].includes(
          String(p.networkPolicy),
        )
      ) {
        fail(`${pp}.networkPolicy`, "invalid network policy");
      }
      if (
        p.networkPolicy === "public_https_only" &&
        !String(p.url).startsWith("https:")
      ) {
        fail(`${pp}.url`, "this command requires HTTPS");
      }
      if (
        p.disposition !== undefined &&
        !["current_tab", "new_tab"].includes(String(p.disposition))
      ) {
        fail(`${pp}.disposition`, "invalid disposition");
      }
      break;
    case "create_tab":
      params(p, ["url", "active"], ["url"], pp);
      safeUrl(p.url, `${pp}.url`);
      if (p.active !== undefined && typeof p.active !== "boolean") {
        fail(`${pp}.active`, "expected a boolean");
      }
      break;
    case "navigate_current_tab":
      params(p, ["url"], ["url"], pp);
      safeUrl(p.url, `${pp}.url`);
      break;
    case "close_tab":
      params(p, [], [], pp);
      break;
    case "switch_tab":
      params(p, ["direction"], ["direction"], pp);
      if (!["next", "previous"].includes(String(p.direction))) {
        fail(`${pp}.direction`, "invalid direction");
      }
      break;
    case "scroll_to_selector":
      params(p, ["selector", "origin", "behavior", "block"], ["selector"], pp);
      safeSelector(p.selector, `${pp}.selector`);
      if (p.origin !== undefined) safeOrigin(p.origin, `${pp}.origin`);
      if (
        p.behavior !== undefined &&
        !["auto", "smooth"].includes(String(p.behavior))
      ) {
        fail(`${pp}.behavior`, "invalid scroll behavior");
      }
      if (
        p.block !== undefined &&
        !["start", "center", "end", "nearest"].includes(String(p.block))
      ) {
        fail(`${pp}.block`, "invalid scroll alignment");
      }
      break;
    case "click_selector":
    case "focus_field":
      params(p, ["selector", "origin"], ["selector"], pp);
      safeSelector(p.selector, `${pp}.selector`);
      if (p.origin !== undefined) safeOrigin(p.origin, `${pp}.origin`);
      break;
    case "type_text":
      params(
        p,
        ["selector", "origin", "text", "containsSensitiveData"],
        ["selector", "text", "containsSensitiveData"],
        pp,
      );
      safeSelector(p.selector, `${pp}.selector`);
      if (p.origin !== undefined) safeOrigin(p.origin, `${pp}.origin`);
      noSecretMaterial(string(p.text, `${pp}.text`, 0, 4_000), `${pp}.text`);
      if (p.containsSensitiveData !== false) {
        fail(`${pp}.containsSensitiveData`, "must be false");
      }
      break;
    case "protected_webhook":
      params(
        p,
        ["configurationId", "payload"],
        ["configurationId", "payload"],
        pp,
      );
      identifier(p.configurationId, `${pp}.configurationId`);
      noSecretMaterial(
        string(p.payload, `${pp}.payload`, 0, 8_000),
        `${pp}.payload`,
      );
      break;
    case "discord_webhook":
      params(
        p,
        ["secretRef", "message", "fallback"],
        ["secretRef", "message"],
        pp,
      );
      identifier(p.secretRef, `${pp}.secretRef`);
      noSecretMaterial(
        string(p.message, `${pp}.message`, 1, 2_000),
        `${pp}.message`,
      );
      if (p.fallback !== undefined && p.fallback !== "local_receipt") {
        fail(`${pp}.fallback`, "invalid fallback");
      }
      break;
    case "claude_workflow":
      params(
        p,
        ["configurationId", "workflowId", "input"],
        ["configurationId", "workflowId", "input"],
        pp,
      );
      identifier(p.configurationId, `${pp}.configurationId`);
      identifier(p.workflowId, `${pp}.workflowId`);
      noSecretMaterial(
        string(p.input, `${pp}.input`, 0, 8_000),
        `${pp}.input`,
      );
      break;
    case "speak_text":
      params(p, ["text", "rate", "voice"], ["text"], pp);
      noSecretMaterial(
        string(p.text, `${pp}.text`, 1, 500),
        `${pp}.text`,
      );
      if (p.rate !== undefined) number(p.rate, `${pp}.rate`, 0.25, 2);
      if (p.voice !== undefined) string(p.voice, `${pp}.voice`, 0, 80);
      break;
    case "show_notification":
      params(p, ["title", "body"], ["title", "body"], pp);
      string(p.title, `${pp}.title`, 1, 120);
      noSecretMaterial(
        string(p.body, `${pp}.body`, 0, 500),
        `${pp}.body`,
      );
      break;
    case "show_overlay":
      params(
        p,
        ["title", "body", "durationMs"],
        ["title", "body", "durationMs"],
        pp,
      );
      string(p.title, `${pp}.title`, 1, 120);
      string(p.body, `${pp}.body`, 0, 500);
      number(p.durationMs, `${pp}.durationMs`, 250, 30_000, true);
      break;
    case "media_control":
      params(p, ["command"], ["command"], pp);
      if (!["play", "pause", "toggle_play_pause"].includes(String(p.command))) {
        fail(`${pp}.command`, "invalid media command");
      }
      break;
    case "bolt_prompt":
      params(p, ["prompt"], ["prompt"], pp);
      noSecretMaterial(
        string(p.prompt, `${pp}.prompt`, 1, 500),
        `${pp}.prompt`,
      );
      break;
    case "spotify_next_track":
      params(p, [], [], pp);
      break;
    case "set_tab_zoom":
      params(p, ["factor"], ["factor"], pp);
      number(p.factor, `${pp}.factor`, 0.25, 5);
      break;
    case "wait":
      params(p, ["durationMs"], ["durationMs"], pp);
      number(p.durationMs, `${pp}.durationMs`, 0, 30_000, true);
      break;
    default:
      fail(
        `${path}.type`,
        "unsupported or dangerous action; native, shell, OS, clipboard, and script actions are forbidden",
      );
  }
  return item as BrowserCommandAction;
}

function parseStep(value: unknown, index: number): CommandStep {
  const path = `command.plan.steps[${index}]`;
  const step = record(value, path);
  exactKeys(
    step,
    ["id", "action", "timeoutMs", "onFailure", "confirmation"],
    path,
  );
  identifier(step.id, `${path}.id`);
  parseAction(step.action, `${path}.action`);
  number(step.timeoutMs, `${path}.timeoutMs`, 100, 60_000, true);
  failurePolicy(step.onFailure, `${path}.onFailure`);
  confirmation(step.confirmation, `${path}.confirmation`);
  return step as CommandStep;
}

function parsePlan(value: unknown): CommandPlan {
  const path = "command.plan";
  const plan = record(value, path);
  exactKeys(
    plan,
    [
      "schemaVersion",
      "id",
      "name",
      "description",
      "steps",
      "timeoutMs",
      "onFailure",
      "confirmation",
      "createdSource",
      "secretReferences",
    ],
    path,
  );
  if (plan.schemaVersion !== 1) fail(`${path}.schemaVersion`, "must be 1");
  identifier(plan.id, `${path}.id`);
  string(plan.name, `${path}.name`, 1, 80);
  noSecretMaterial(
    string(plan.description, `${path}.description`, 0, 500),
    `${path}.description`,
  );
  if (!Array.isArray(plan.steps) || plan.steps.length < 1 || plan.steps.length > 50) {
    fail(`${path}.steps`, "expected 1 to 50 actions");
  }
  plan.steps.forEach(parseStep);
  number(plan.timeoutMs, `${path}.timeoutMs`, 100, 300_000, true);
  failurePolicy(plan.onFailure, `${path}.onFailure`);
  confirmation(plan.confirmation, `${path}.confirmation`);
  if (
    !["visual", "natural_language", "demo_recording", "import"].includes(
      String(plan.createdSource),
    )
  ) {
    fail(`${path}.createdSource`, "invalid source");
  }
  if (!Array.isArray(plan.secretReferences) || plan.secretReferences.length > 20) {
    fail(`${path}.secretReferences`, "expected no more than 20 references");
  }
  plan.secretReferences.forEach((value, index) => {
    const refPath = `${path}.secretReferences[${index}]`;
    const ref = record(value, refPath);
    exactKeys(ref, ["id", "provider", "purpose", "storage"], refPath);
    identifier(ref.id, `${refPath}.id`);
    if (
      ![
        "discord",
        "slack",
        "http_bearer",
        "http_basic",
        "http_api_key",
        "claude",
      ].includes(String(ref.provider))
    ) {
      fail(`${refPath}.provider`, "invalid provider");
    }
    string(ref.purpose, `${refPath}.purpose`, 1, 120);
    if (
      ![
        "server_environment",
        "extension_local",
        "keychain_or_server_environment",
      ].includes(String(ref.storage))
    ) {
      fail(`${refPath}.storage`, "invalid reference storage");
    }
  });
  return plan as CommandPlan;
}

export function parseSignalCommand(value: unknown): SignalCommand {
  const command = record(value, "command");
  exactKeys(
    command,
    [
      "schemaVersion",
      "id",
      "gesture",
      "name",
      "description",
      "source",
      "plan",
      "createdAt",
      "updatedAt",
      "enabled",
    ],
    "command",
  );
  if (command.schemaVersion !== 1) fail("command.schemaVersion", "must be 1");
  identifier(command.id, "command.id");
  if (!GESTURE_IDS.includes(command.gesture as (typeof GESTURE_IDS)[number])) {
    fail("command.gesture", "unsupported gesture");
  }
  string(command.name, "command.name", 1, 80);
  noSecretMaterial(
    string(command.description, "command.description", 0, 500),
    "command.description",
  );
  if (
    !["preset", "natural_language", "recording", "hybrid"].includes(
      String(command.source),
    )
  ) {
    fail("command.source", "invalid source");
  }
  parsePlan(command.plan);
  for (const key of ["createdAt", "updatedAt"] as const) {
    const value = string(command[key], `command.${key}`, 10, 64);
    if (!value.includes("T") || Number.isNaN(Date.parse(value))) {
      fail(`command.${key}`, "expected an ISO-8601 timestamp");
    }
  }
  if (typeof command.enabled !== "boolean") {
    fail("command.enabled", "expected a boolean");
  }
  return command as SignalCommand;
}

export function safeParseSignalCommand(
  value: unknown,
): ValidationResult<SignalCommand> {
  try {
    return { success: true, data: parseSignalCommand(value) };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error : new TypeError("Invalid command"),
    };
  }
}

export const signalCommandSchema = {
  parse: parseSignalCommand,
  safeParse: safeParseSignalCommand,
};

export function parseStoredProfile(value: unknown): StoredProfile {
  const profile = record(value, "profile");
  exactKeys(
    profile,
    [
      "schemaVersion",
      "id",
      "name",
      "description",
      "commands",
      "settings",
      "tuning",
    ],
    "profile",
  );
  if (profile.schemaVersion !== 1) fail("profile.schemaVersion", "must be 1");
  identifier(profile.id, "profile.id");
  string(profile.name, "profile.name", 1, 80);
  string(profile.description, "profile.description", 0, 500);
  if (!Array.isArray(profile.commands) || profile.commands.length > 9) {
    fail("profile.commands", "expected no more than nine commands");
  }
  const commands = profile.commands.map(parseSignalCommand);
  if (
    new Set(
      commands.map((command) => command.gesture),
    ).size !== profile.commands.length
  ) {
    fail("profile.commands", "gesture mappings must be unique");
  }
  if (profile.settings !== undefined) {
    const settings = record(profile.settings, "profile.settings");
    exactKeys(
      settings,
      [
        "mode",
        "hideSiteCursor",
        "resetCursorOnTabChange",
        "naturalScroll",
        "useSyncSettings",
      ],
      "profile.settings",
    );
    if (
      settings.mode !== undefined &&
      !["control", "commands", "paused"].includes(String(settings.mode))
    ) {
      fail("profile.settings.mode", "invalid Signal mode");
    }
    for (const key of [
      "hideSiteCursor",
      "resetCursorOnTabChange",
      "naturalScroll",
      "useSyncSettings",
    ]) {
      if (settings[key] !== undefined && typeof settings[key] !== "boolean") {
        fail(`profile.settings.${key}`, "expected a boolean");
      }
    }
  }
  if (profile.tuning !== undefined) {
    const tuning = record(profile.tuning, "profile.tuning");
    exactKeys(
      tuning,
      [
        "holdMs",
        "cooldownMs",
        "minimumConfidence",
        "pointerSensitivity",
        "pointerSmoothing",
        "pointerDeadZone",
        "pointerAcceleration",
        "pointerMaxFrameMovement",
        "scrollRateLimitMs",
        "zoomRateLimitMs",
      ],
      "profile.tuning",
    );
    for (const [key, candidate] of Object.entries(tuning)) {
      if (typeof candidate !== "number" || !Number.isFinite(candidate)) {
        fail(`profile.tuning.${key}`, "expected a finite number");
      }
    }
  }
  return { ...(profile as StoredProfile), commands };
}
