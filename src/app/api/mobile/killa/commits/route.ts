import type { NextRequest } from "next/server";
import { killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";

/** `GET /api/mobile/killa/commits?limit=50` (≤ 200) → `{ commits: [{hash, date, author, subject}] }`. */
export const GET = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  return Response.json({ commits: await killaEngine.commits(req.nextUrl.searchParams.get("limit")) });
});
