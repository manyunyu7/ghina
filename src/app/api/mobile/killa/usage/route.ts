import type { NextRequest } from "next/server";
import { killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";

/**
 * `GET /api/mobile/killa/usage?days=30` (≤ 90) → `{since, days:[{date, turns, …tokens, costUsd}],
 * byModel, total}` — all engine runs; `costUsd` is an API-price estimate, not a bill.
 */
export const GET = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  return Response.json(await killaEngine.usage(req.nextUrl.searchParams.get("days") ?? 30));
});
