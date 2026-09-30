import type { NextRequest } from "next/server";
import { listKillaMessages, requireKillaSessionUser } from "@/lib/killa";
import { handleKilla } from "@/lib/mobile/killa";

/**
 * `GET /api/killa/messages?limit=` — newest page of the chat log for the web poll (a
 * GET route rather than a Server Action: actions are queued behind a running send).
 */
export const GET = handleKilla(async (req: NextRequest) => {
  const user = await requireKillaSessionUser();
  const res = await listKillaMessages(user.id, { limit: req.nextUrl.searchParams.get("limit") ?? 30 });
  return Response.json(res, { headers: { "Cache-Control": "no-store" } });
});
