import {
  apiError,
  enforceRateLimit,
  json,
  preflight,
  readJsonBody,
  rejectDisallowedOrigin,
} from "@/lib/api/http";
import { makePlan, validatePlannerInput } from "@/lib/api/planner";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const originError = rejectDisallowedOrigin(request);
  if (originError) return originError;
  const limited = enforceRateLimit(request, "plan");
  if (limited) return limited;
  const body = await readJsonBody(request, 16 * 1024);
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
      "Signal supports planner schema version 1.",
      ["schemaVersion"],
    );
  }
  const validated = validatePlannerInput(body.value);
  if (!validated.ok) {
    return apiError(
      request,
      422,
      "validation_failed",
      "Planner request did not match schema version 1.",
      validated.fields,
    );
  }
  return json(request, await makePlan(validated.value));
}

export async function OPTIONS(request: Request) {
  return preflight(request);
}
