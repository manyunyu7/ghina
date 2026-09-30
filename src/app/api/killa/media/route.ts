import type { NextRequest } from "next/server";
import { killaEngine, requireKillaSessionUser } from "@/lib/killa";
import { handleKilla, killaMediaResponse } from "@/lib/mobile/killa";

/**
 * `GET /api/killa/media?path=` — a file Killa produced (reply attachment), streamed from
 * the engine's GET /v1/media. Web session + allowlist (401 / 404). Used as <img> src.
 */
export const GET = handleKilla(async (req: NextRequest) => {
  await requireKillaSessionUser();
  const path = req.nextUrl.searchParams.get("path") ?? "";
  return killaMediaResponse(path, await killaEngine.media(path));
});
