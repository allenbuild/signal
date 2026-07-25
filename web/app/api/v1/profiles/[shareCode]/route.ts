import { apiError, enforceRateLimit, json, preflight } from "@/lib/api/http";
import { getProfile, validShareCode } from "@/lib/api/profiles";

export const dynamic = "force-dynamic";

export async function GET(
  request: Request,
  context: { params: Promise<{ shareCode: string }> },
) {
  const limited = enforceRateLimit(request, "profiles-read");
  if (limited) return limited;
  const { shareCode } = await context.params;
  if (!validShareCode(shareCode)) {
    return apiError(request, 400, "invalid_share_code", "Share code is not valid.");
  }
  const profile = getProfile(shareCode);
  if (!profile) {
    return apiError(request, 404, "profile_not_found", "No public profile matches this share code.");
  }
  return json(request, profile);
}

export async function OPTIONS(request: Request) {
  return preflight(request);
}
