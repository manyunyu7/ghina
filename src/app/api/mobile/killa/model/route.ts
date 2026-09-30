import { killaChatKey, killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";
import { readJson } from "@/lib/mobile/http";
import { killaSetModelSchema } from "@/lib/schemas";

/**
 * The chat's persisted Killa model — engine-side, shared with WhatsApp's `/model`.
 * `GET /api/mobile/killa/model` → `{ model: string|null, options: string[] }` (null = engine default).
 * `POST /api/mobile/killa/model {model}` → `{ ok, model }` — `"default"` clears (model null).
 */
export const GET = handleKilla(async (req: Request) => {
  const user = await requireKillaMobileUser(req);
  return Response.json(await killaEngine.getModel(killaChatKey(user.id)));
});

export const POST = handleKilla(async (req: Request) => {
  const user = await requireKillaMobileUser(req);
  const body = await readJson(req, killaSetModelSchema);
  return Response.json(await killaEngine.setModel(killaChatKey(user.id), body));
});
