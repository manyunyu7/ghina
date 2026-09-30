import { ingestKillaMirror, isKillaMirrorAuthorized } from "@/lib/killa";
import { handleKilla } from "@/lib/mobile/killa";
import { HttpError, readJson } from "@/lib/mobile/http";
import { killaMirrorSchema } from "@/lib/schemas";

/**
 * killa-engine mirror hook (docs/killa.md "Mirror"): the WhatsApp side of the shared
 * `wa:` conversation. `Authorization: Bearer <KILLA_MIRROR_TOKEN>` (constant-time; no
 * user session). Body `{channel:"wa", number, messages:[{role, text, at}]}` → rows for
 * the Killa owner with channel "wa". → `{ok, inserted, skipped}` (duplicates skipped).
 */
export const POST = handleKilla(async (req: Request) => {
  if (!isKillaMirrorAuthorized(req.headers.get("authorization"))) throw new HttpError(401, "unauthorized");
  const res = await ingestKillaMirror(await readJson(req, killaMirrorSchema));
  return Response.json({ ok: true, ...res });
});
