import { json, preflight } from "@/lib/api/http";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return json(request, {
    schemaVersion: 1,
    ok: true,
    service: "signal-api",
    apiVersion: "v1",
    cameraDataAccepted: false,
  });
}

export async function OPTIONS(request: Request) {
  return preflight(request);
}
