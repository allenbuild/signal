import {
  getRequestId,
  jsonResponse,
} from "../../../../lib/rate-limit";

export function GET(request: Request) {
  const requestId = getRequestId(request);
  return jsonResponse(
    {
      schemaVersion: 1,
      status: "ok",
    },
    requestId,
    { status: 200 },
  );
}
