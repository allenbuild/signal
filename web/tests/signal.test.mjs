import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

process.env.SIGNAL_DOWNLOAD_URL = "https://downloads.example/Signal-0.1.0-arm64.zip";
process.env.SIGNAL_RELEASE_VERSION = "0.1.0-rc1";
process.env.SIGNAL_RELEASE_COMMIT = "abc1234";
process.env.SIGNAL_RELEASE_SHA256 = "a".repeat(64);
process.env.SIGNAL_RELEASE_ARCHITECTURE = "Apple silicon (arm64) only";
process.env.SIGNAL_SIGNING_STATUS = "Ad hoc";
process.env.SIGNAL_NOTARIZATION_STATUS = "Not notarized";

const workerUrl = new URL("../dist/server/index.js", import.meta.url);
workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
const { default: worker } = await import(workerUrl.href);
const env = {
  ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) },
};
const context = { waitUntil() {}, passThroughOnException() {} };

function request(path, init = {}) {
  return worker.fetch(new Request(`https://signal.example${path}`, init), env, context);
}

function post(path, body, headers = {}) {
  return request(path, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const sharedPlannerRequest = {
  schemaVersion: 1,
  requestId: "demo-request-1",
  request:
    "When I give a thumbs up, open my focus playlist, say Focus mode, and send Demo complete to Discord.",
  targetGesture: "thumbs_up",
  actionCatalog: ["open_url", "speak_text", "discord_webhook"],
};

const sharedProfileCreateRequest = {
  profile: {
    schemaVersion: 1,
    id: "signal.example.shared",
    name: "Shared focus profile",
    description: "A minimal unlisted profile example.",
    preferredMode: "commands",
    hybridOneBehavior: "pointer",
    mappings: [],
    share: { visibility: "unlisted" },
  },
};

test("renders the finished Signal landing page without starter metadata", async () => {
  const response = await request("/");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /<title>Signal — Your hand already knows the shortcut<\/title>/i);
  assert.match(html, /Your hand already knows the shortcut/);
  assert.match(html, /Point\. Pinch\. Program\./);
  assert.match(html, /Try the local profile builder/);
  assert.match(html, /href="#main-content"[^>]*>Skip to main content/);
  assert.match(html, /<main id="main-content">/);
  assert.match(html, /aria-pressed="true"/);
  assert.match(html, /role="status"/);
  assert.match(html, /New links are temporary until this worker restarts/);
  assert.match(html, /controlled reviewable[\s\S]*demo timeline/i);
  assert.match(html, /Generic network actions are disabled/);
  assert.match(html, /closes the output gate and requests macro cancellation/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape|react-loading-skeleton/i);
  assert.doesNotMatch(html, /editable macro engine|stops touch output and macros immediately/i);
});

test("keeps keyboard focus visible and mobile navigation available", async () => {
  const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");
  assert.match(css, /:focus-visible\s*\{/);
  assert.match(css, /\.skip-link:focus-visible/);
  assert.match(css, /\.nav-links\s*\{[\s\S]*overflow-x:\s*auto/);
  assert.doesNotMatch(css, /outline:\s*0|\.nav-links\s*\{\s*display:\s*none/);
});

test("download page shows environment-provided release evidence and honest Gatekeeper steps", async () => {
  const response = await request("/download");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /macOS 13 or later is required/);
  assert.match(html, /Apple silicon \(arm64\) only/);
  assert.match(html, /0\.1\.0-rc1/);
  assert.match(html, /abc1234/);
  assert.match(html, new RegExp("a{64}"));
  assert.match(html, /Ad hoc/);
  assert.match(html, /Not notarized/);
  assert.match(html, /Control-click Signal and choose Open/);
  assert.match(html, /Do not disable Gatekeeper/);
});

test("prior-work page preserves zero-file repository evidence without editable claims", async () => {
  const response = await request("/prior-work");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /night-hack-start/);
  assert.match(html, /contains zero tracked files/);
  assert.match(html, /team-supplied disclosure/);
  assert.match(html, /controlled Teach by Demo timeline/);
  assert.doesNotMatch(html, /editable macro engine/);
});

test("returns a deterministic, non-secret health response", async () => {
  const response = await request("/api/v1/health");
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    schemaVersion: 1,
    ok: true,
    service: "signal-api",
    apiVersion: "v1",
    cameraDataAccepted: false,
  });
});

test("planner accepts the frozen seeded request and emits the v1 envelope", async () => {
  const response = await post("/api/v1/plan", sharedPlannerRequest, {
    "cf-connecting-ip": "203.0.113.10",
  });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.requestId, sharedPlannerRequest.requestId);
  assert.equal(result.status, "planned");
  assert.equal(result.usedDeterministicFallback, true);
  assert.equal(result.plan.schemaVersion, 1);
  assert.deepEqual(
    result.plan.steps.map((step) => step.action.type),
    sharedPlannerRequest.actionCatalog,
  );
  assert.equal(result.plan.confirmation.mode, "first_run");
  assert.equal(result.plan.secretReferences[0].storage, "keychain_or_server_environment");
});

test("planner rejects future versions, unknown fields, and catalog escalation", async () => {
  const future = await post(
    "/api/v1/plan",
    { ...sharedPlannerRequest, schemaVersion: 2 },
    { "cf-connecting-ip": "203.0.113.11" },
  );
  assert.equal(future.status, 422);
  assert.equal((await future.json()).error.code, "unsupported_schema_version");

  const unknown = await post(
    "/api/v1/plan",
    { ...sharedPlannerRequest, rawCode: "do shell things" },
    { "cf-connecting-ip": "203.0.113.12" },
  );
  assert.equal(unknown.status, 422);

  const underscoped = await post(
    "/api/v1/plan",
    { ...sharedPlannerRequest, actionCatalog: ["open_url"] },
    { "cf-connecting-ip": "203.0.113.13" },
  );
  assert.equal(underscoped.status, 200);
  assert.equal((await underscoped.json()).status, "needs_clarification");
});

test("profile service accepts frozen shape and returns a canonical share URL", async () => {
  const created = await post(
    "/api/v1/profiles",
    sharedProfileCreateRequest,
    { "cf-connecting-ip": "203.0.113.20" },
  );
  assert.equal(created.status, 201);
  const receipt = await created.json();
  assert.equal(receipt.schemaVersion, 1);
  assert.match(receipt.shareCode, /^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/);
  assert.equal(receipt.profileURL, `https://signal.example/p/${receipt.shareCode}`);

  const fetched = await request(`/api/v1/profiles/${receipt.shareCode}`, {
    headers: { "cf-connecting-ip": "203.0.113.21" },
  });
  assert.equal(fetched.status, 200);
  const profile = await fetched.json();
  assert.equal(profile.id, "signal.example.shared");
  assert.equal(profile.share.shareCode, receipt.shareCode);
});

test("seeded public profile is always available", async () => {
  const response = await request("/api/v1/profiles/SIG1-SGNL2626", {
    headers: { "cf-connecting-ip": "203.0.113.22" },
  });
  assert.equal(response.status, 200);
  const profile = await response.json();
  assert.equal(profile.schemaVersion, 1);
  assert.equal(profile.mappings.length, 2);
  assert.equal(profile.share.shareCode, "SIG1-SGNL2626");
});

test("profiles reject duplicate IDs, undeclared secrets, unsafe URLs, and disabled HTTP", async () => {
  const plannedResponse = await post("/api/v1/plan", sharedPlannerRequest, {
    "cf-connecting-ip": "203.0.113.23",
  });
  const { plan } = await plannedResponse.json();
  const profileWith = (candidatePlan) => ({
    profile: {
      schemaVersion: 1,
      id: "signal.security.test",
      name: "Security test",
      description: "Adversarial profile fixture.",
      preferredMode: "commands",
      hybridOneBehavior: "pointer",
      mappings: [{
        gesture: "thumbs_up",
        enabled: true,
        holdDurationMs: 600,
        cooldownMs: 900,
        activation: "one_shot",
        allowedBundleIdentifiers: [],
        plan: candidatePlan,
      }],
      share: { visibility: "unlisted" },
    },
  });

  const duplicate = structuredClone(plan);
  duplicate.steps[1].id = duplicate.steps[0].id;
  const duplicateResponse = await post("/api/v1/profiles", profileWith(duplicate), {
    "cf-connecting-ip": "203.0.113.24",
  });
  assert.equal(duplicateResponse.status, 422);

  const undeclared = structuredClone(plan);
  undeclared.secretReferences = [];
  const undeclaredResponse = await post("/api/v1/profiles", profileWith(undeclared), {
    "cf-connecting-ip": "203.0.113.25",
  });
  assert.equal(undeclaredResponse.status, 422);

  const privateUrl = structuredClone(plan);
  privateUrl.steps[0].action.parameters.url = "https://127.0.0.1/private";
  const privateResponse = await post("/api/v1/profiles", profileWith(privateUrl), {
    "cf-connecting-ip": "203.0.113.26",
  });
  assert.equal(privateResponse.status, 422);

  const genericHTTP = structuredClone(plan);
  genericHTTP.steps = [{
    id: "http",
    action: {
      type: "http_request",
      parameters: {
        method: "GET",
        url: "https://example.com/status",
        networkPolicy: "public_https_only",
        headers: [],
        secretRefs: [],
        maximumResponseBytes: 1024,
      },
    },
    timeoutMs: 5000,
    onFailure: "stop",
    confirmation: { mode: "every_run", reason: "External network request." },
  }];
  genericHTTP.secretReferences = [];
  const httpResponse = await post("/api/v1/profiles", profileWith(genericHTTP), {
    "cf-connecting-ip": "203.0.113.27",
  });
  assert.equal(httpResponse.status, 422);
  assert.equal((await httpResponse.json()).error.code, "action_disabled");
});

test("request size, media type, origin, and rate limits are enforced", async () => {
  const wrongType = await request("/api/v1/plan", {
    method: "POST",
    headers: { "content-type": "text/plain", "cf-connecting-ip": "203.0.113.30" },
    body: "{}",
  });
  assert.equal(wrongType.status, 415);

  const tooLarge = await post("/api/v1/plan", {
    ...sharedPlannerRequest,
    request: "x".repeat(17_000),
  }, { "cf-connecting-ip": "203.0.113.33" });
  assert.equal(tooLarge.status, 413);

  const badOrigin = await post("/api/v1/plan", sharedPlannerRequest, {
    origin: "https://attacker.example",
    "cf-connecting-ip": "203.0.113.31",
  });
  assert.equal(badOrigin.status, 403);

  let final;
  for (let index = 0; index < 41; index += 1) {
    final = await post("/api/v1/integrations/discord", {
      schemaVersion: 1,
      message: "Demo complete",
    }, { "cf-connecting-ip": "203.0.113.32" });
  }
  assert.equal(final.status, 429);
  assert.equal((await final.json()).error.code, "rate_limited");
});

test("Discord safely records a deterministic fallback receipt", async () => {
  const response = await post("/api/v1/integrations/discord", {
    schemaVersion: 1,
    message: "Demo complete",
    webhookReference: "demo-discord-webhook",
  }, { "cf-connecting-ip": "203.0.113.40" });
  assert.equal(response.status, 202);
  const result = await response.json();
  assert.equal(result.receipt.status, "fallback_recorded");
  assert.equal(result.receipt.fallback, true);
  assert.doesNotMatch(JSON.stringify(result), /https:\/\/discord|webhook.*token/i);
});
