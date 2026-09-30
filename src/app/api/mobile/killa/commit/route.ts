import type { NextRequest } from "next/server";
import { killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";
import { HttpError } from "@/lib/mobile/http";

/**
 * `POST /api/mobile/killa/commit {message?}` → `{ ok, hash }` — commits Killa's workspace;
 * `hash` is null when there was nothing to commit. An empty body is allowed.
 */
export const POST = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  const text = await req.text();
  let body: unknown = {};
  if (text.trim()) {
    try {
      body = JSON.parse(text);
    } catch {
      throw new HttpError(400, "Invalid JSON body");
    }
  }
  return Response.json(await killaEngine.commit(body));
});
