#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const readJSON = (relativePath) =>
  JSON.parse(readFileSync(join(root, relativePath), "utf8"));
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const schemaPaths = [
  "shared/action-plan.schema.json",
  "shared/profile.schema.json",
  "shared/planner-response.schema.json",
];
const examplePaths = [
  "shared/examples/planner-request.json",
  "shared/examples/planner-response.json",
  "shared/examples/profile-create-request.json",
  "shared/examples/profile-create-response.json",
];

const schemas = schemaPaths.map(readJSON);
const examples = Object.fromEntries(
  examplePaths.map((path) => [path, readJSON(path)]),
);
const seed = readJSON("shared/seeded-demo-profile.json");

for (const [index, schema] of schemas.entries()) {
  assert(
    schema.$schema === "https://json-schema.org/draft/2020-12/schema",
    `${schemaPaths[index]} must use draft 2020-12`,
  );
}
assert(
  schemas[0].properties.schemaVersion.const === 1,
  "action-plan schemaVersion must be const 1",
);
assert(
  schemas[1].properties.schemaVersion.const === 1,
  "profile schemaVersion must be const 1",
);

const allowedGestures = new Set([
  "one",
  "two",
  "three",
  "four",
  "five",
  "fist",
  "thumbs_up",
  "thumbs_down",
  "c_shape",
]);
const allowedActions = new Set([
  "open_application",
  "open_url",
  "open_deep_link",
  "keyboard_shortcut",
  "type_text",
  "wait",
  "show_notification",
  "speak_text",
  "play_sound",
  "set_clipboard",
  "read_clipboard_and_transform",
  "run_apple_shortcut",
  "run_applescript_template",
  "http_request",
  "discord_webhook",
  "slack_webhook",
  "media_control",
  "set_volume",
  "show_overlay",
  "focus_application",
  "click_screen_point",
  "scroll_amount",
  "zoom_steps",
  "conditional",
]);
const forbiddenRawKeys = new Set([
  "token",
  "password",
  "apikey",
  "api_key",
  "authorization",
  "cookie",
  "webhookurl",
  "webhook_url",
  "secretvalue",
  "secret_value",
]);

function rejectRawSecretKeys(value, path = "$") {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => rejectRawSecretKeys(entry, `${path}[${index}]`));
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    assert(
      !forbiddenRawKeys.has(key.toLowerCase()),
      `${path}.${key} is a forbidden raw-secret field`,
    );
    rejectRawSecretKeys(child, `${path}.${key}`);
  }
}

function validateAction(action, path, allowConditional = true) {
  assert(action && typeof action === "object", `${path} must be an object`);
  assert(allowedActions.has(action.type), `${path}.type is unsupported`);
  assert(action.parameters && typeof action.parameters === "object", `${path}.parameters missing`);
  if (action.type === "conditional") {
    assert(allowConditional, `${path} contains a recursive conditional`);
    for (const branch of ["ifTrue", "ifFalse"]) {
      const actions = action.parameters[branch];
      assert(Array.isArray(actions) && actions.length <= 10, `${path}.${branch} exceeds 10`);
      actions.forEach((entry, index) =>
        validateAction(entry, `${path}.${branch}[${index}]`, false),
      );
    }
  }
  if (action.type === "open_url" || action.type === "http_request") {
    const { url, networkPolicy } = action.parameters;
    assert(/^https:\/\/[^\s]+$/.test(url), `${path} must use HTTPS`);
    assert(networkPolicy === "public_https_only", `${path} must use public_https_only`);
  }
}

function validatePlan(plan, path) {
  assert(plan.schemaVersion === 1, `${path} has unsupported_schema_version`);
  assert(Array.isArray(plan.steps) && plan.steps.length >= 1 && plan.steps.length <= 50, `${path}.steps out of bounds`);
  assert(Number.isInteger(plan.timeoutMs) && plan.timeoutMs >= 100 && plan.timeoutMs <= 300000, `${path}.timeoutMs out of bounds`);
  const stepIds = new Set();
  for (const [index, step] of plan.steps.entries()) {
    const stepPath = `${path}.steps[${index}]`;
    assert(!stepIds.has(step.id), `${stepPath}.id is duplicated`);
    stepIds.add(step.id);
    assert(Number.isInteger(step.timeoutMs) && step.timeoutMs >= 100 && step.timeoutMs <= 60000, `${stepPath}.timeoutMs out of bounds`);
    validateAction(step.action, `${stepPath}.action`);
  }
  const referenceIds = new Set();
  for (const reference of plan.secretReferences ?? []) {
    assert(!referenceIds.has(reference.id), `${path} has duplicate secret reference`);
    referenceIds.add(reference.id);
    assert(
      reference.storage === "keychain_or_server_environment",
      `${path} secret storage contract changed`,
    );
  }
  for (const step of plan.steps) {
    const ref = step.action.parameters?.secretRef;
    if (ref) assert(referenceIds.has(ref), `${path} uses undeclared secret reference ${ref}`);
    for (const item of step.action.parameters?.secretRefs ?? []) {
      assert(referenceIds.has(item), `${path} uses undeclared secret reference ${item}`);
    }
  }
  rejectRawSecretKeys(plan, path);
}

function validateProfile(profile) {
  assert(profile.schemaVersion === 1, "profile has unsupported_schema_version");
  assert(Array.isArray(profile.mappings) && profile.mappings.length <= 9, "profile has too many mappings");
  const gestures = new Set();
  for (const [index, mapping] of profile.mappings.entries()) {
    assert(allowedGestures.has(mapping.gesture), `mapping ${index} gesture unsupported`);
    assert(!gestures.has(mapping.gesture), `mapping ${index} duplicates ${mapping.gesture}`);
    gestures.add(mapping.gesture);
    validatePlan(mapping.plan, `profile.mappings[${index}].plan`);
  }
  if (profile.share.shareCode) {
    assert(
      /^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/.test(profile.share.shareCode),
      "shareCode format invalid",
    );
  }
  rejectRawSecretKeys(profile);
}

validateProfile(seed);
const planner = examples["shared/examples/planner-response.json"];
assert(planner.schemaVersion === 1 && planner.status === "planned", "planner example envelope invalid");
validatePlan(planner.plan, "planner.plan");
validateProfile(examples["shared/examples/profile-create-request.json"].profile);

assert(examples["shared/examples/planner-request.json"].schemaVersion === 1, "planner request example version invalid");
assert(/^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/.test(examples["shared/examples/profile-create-response.json"].shareCode), "profile response share code invalid");

assert(
  (() => {
    try {
      validateProfile({ ...seed, schemaVersion: 2 });
      return false;
    } catch {
      return true;
    }
  })(),
  "future profile versions must be rejected",
);
assert(
  (() => {
    try {
      validateProfile({ ...seed, mappings: [...seed.mappings, seed.mappings[0]] });
      return false;
    } catch {
      return true;
    }
  })(),
  "duplicate gestures must be rejected",
);

console.log(
  `validated ${schemaPaths.length} schemas, ${examplePaths.length} examples, ` +
    `${seed.mappings.length} seeded mappings, and negative version/duplicate tests`,
);
