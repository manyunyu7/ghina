import type { NextRequest } from "next/server";
import { killaEngine } from "@/lib/killa";
import { handleKilla, killaMediaResponse, requireKillaMobileUser } from "@/lib/mobile/killa";

/**
 * `GET /api/mobile/killa/media?path=` — raw file for an `engine` attachment (Content-Type
 * from the engine; 400 bad path, 404 missing, 413 > 15 MB). `upload` attachments are
 * plain `/uploads/…` URLs and need no proxy.
 */
export const GET = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  const path = req.nextUrl.searchParams.get("path") ?? "";
  return killaMediaResponse(path, await killaEngine.media(path));
});
