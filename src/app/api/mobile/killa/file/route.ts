import type { NextRequest } from "next/server";
import { killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";

/** `GET /api/mobile/killa/file?path=` → `{ path, content }`; 413 too large, 415 not text. */
export const GET = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  return Response.json(await killaEngine.file(req.nextUrl.searchParams.get("path")));
});
