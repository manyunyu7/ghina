import type { NextRequest } from "next/server";
import { killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";

/** `GET /api/mobile/killa/files?path=` → `{ path, entries: [{name, type: "file"|"dir", size}] }` (read-only). */
export const GET = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  const path = req.nextUrl.searchParams.get("path") ?? "";
  return Response.json({ path, entries: await killaEngine.files(path) });
});
