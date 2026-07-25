import {
  apiError,
  enforceRateLimit,
  json,
  preflight,
  readJsonBody,
  rejectDisallowedOrigin,
} from "@/lib/api/http";
import { saveProfile, validateProfile } from "@/lib/api/profiles";
import { hasOnlyKeys, isPlainObject } from "@/lib/api/http";
import { planContainsActionType } from "@/lib/api/safety";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const originError = rejectDisallowedOrigin(request);
  if (originError) return originError;
  const limited = enforceRateLimit(request, "profiles-write");
  if (limited) return limited;
  const body = await readJsonBody(request, 48 * 1024);
  if (!body.ok) return body.response;
  if (!isPlainObject(body.value) || !hasOnlyKeys(body.value, ["profile"])) {
    return apiError(
      request,
      422,
      "validation_failed",
      "Profile request did not match schema version 1.",
      ["profile"],
    );
  }
  if (
    isPlainObject(body.value.profile) &&
    "schemaVersion" in body.value.profile &&
    body.value.profile.schemaVersion !== 1
  ) {
    return apiError(
      request,
      422,
      "unsupported_schema_version",
      "Signal supports profile schema version 1.",
      ["profile.schemaVersion"],
    );
  }
  const profile = validateProfile(body.value.profile);
  if (!profile.ok) {
    return apiError(
      request,
      422,
      "validation_failed",
      "Profile did not match schema version 1.",
      profile.fields,
    );
  }
  if (profile.value.share.visibility !== "unlisted") {
    return apiError(
      request,
      409,
      "profile_not_shareable",
      "Set profile share visibility to unlisted before publishing.",
      ["profile.share.visibility"],
    );
  }
  if (profile.value.mappings.some((mapping) => planContainsActionType(mapping.plan, "http_request"))) {
    return apiError(
      request,
      422,
      "action_disabled",
      "Public profiles cannot contain generic HTTP request actions in version 1.",
      ["profile.mappings.plan.steps.action.type"],
    );
  }
  const saved = saveProfile(profile.value);
  const profileURL = new URL(`/p/${saved.shareCode}`, request.url).toString();
  return json(
    request,
    {
      schemaVersion: 1,
      shareCode: saved.shareCode,
      profileURL,
    },
    { status: 201 },
  );
}

export async function OPTIONS(request: Request) {
  return preflight(request);
}
