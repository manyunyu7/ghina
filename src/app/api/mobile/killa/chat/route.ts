import type { NextRequest } from "next/server";
import { listKillaMessages, sendKillaMessage } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";
import { readJson } from "@/lib/mobile/http";
import { killaSendSchema } from "@/lib/schemas";

/**
 * Killa chat log (docs/killa.md "Mobile API").
 * `GET /api/mobile/killa/chat?before=<id>&limit=50` → `{ messages (oldest first), nextBefore }`.
 * `POST /api/mobile/killa/chat {text, model?}` → `{ userMessage, reply }` — waits for Killa
 * (up to ~5.5 minutes); the user message is recorded even when Killa fails (502/504).
 */
export const GET = handleKilla(async (req: NextRequest) => {
  const user = await requireKillaMobileUser(req);
  const q = req.nextUrl.searchParams;
  return Response.json(await listKillaMessages(user.id, { before: q.get("before"), limit: q.get("limit") }));
});

export const POST = handleKilla(async (req: NextRequest) => {
  const user = await requireKillaMobileUser(req);
  return Response.json(await sendKillaMessage(user.id, await readJson(req, killaSendSchema)));
});
