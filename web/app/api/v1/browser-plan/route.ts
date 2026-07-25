import {
  apiError,
  enforceRateLimit,
  json,
  preflight,
  readJsonBody,
  rejectDisallowedOrigin,
} from "@/lib/api/http";
import {
  makeBrowserPlan,
  validateBrowserPlannerRequest,
} from "@/lib/signal-commands/planner";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const originError = rejectDisallowedOrigin(request);
  if (originError) return originError;
  const limited = enforceRateLimit(request, "browser-plan");
  if (limited) return limited;
  const body = await readJsonBody(request, 5_100_000);
  if (!body.ok) return body.response;
  if (
    body.value &&
    typeof body.value === "object" &&
    !Array.isArray(body.value) &&
    "schemaVersion" in body.value &&
    body.value.schemaVersion !== 1
  ) {
    return apiError(
      request,
      422,
      "unsupported_schema_version",
      "Signal supports browser-command planner schema version 1.",
      ["schemaVersion"],
    );
  }
  const validated = validateBrowserPlannerRequest(body.value);
  if (!validated.ok) {
    return apiError(
      request,
      422,
      "validation_failed",
      "Browser planner request did not match schema version 1.",
      validated.fields,
    );
  }
  return json(request, await makeBrowserPlan(validated.value));
}

export async function OPTIONS(request: Request) {
  return preflight(request);
}
