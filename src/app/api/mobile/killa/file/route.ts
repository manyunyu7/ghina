import type { NextRequest } from "next/server";
import { killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";
import { readJson } from "@/lib/mobile/http";
import { killaWriteFileSchema } from "@/lib/schemas";

/** `GET /api/mobile/killa/file?path=` → `{ path, content }`; 413 too large, 415 not text. */
export const GET = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  return Response.json(await killaEngine.file(req.nextUrl.searchParams.get("path")));
});

/** `PUT /api/mobile/killa/file {path, content}` → `{ ok, path }` (create or overwrite; content ≤ 1 MB). */
export const PUT = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  return Response.json(await killaEngine.writeFile(await readJson(req, killaWriteFileSchema)));
});

/** `DELETE /api/mobile/killa/file?path=` → `{ ok, path }`. */
export const DELETE = handleKilla(async (req: NextRequest) => {
  await requireKillaMobileUser(req);
  return Response.json(await killaEngine.deleteFile(req.nextUrl.searchParams.get("path")));
});
