import { killaChatKey, killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";

/** `GET /api/mobile/killa/reminders` → `{ reminders: [{id, spec, text, nextAt (epoch ms)}] }`, soonest first. */
export const GET = handleKilla(async (req: Request) => {
  const user = await requireKillaMobileUser(req);
  return Response.json({ reminders: await killaEngine.reminders(killaChatKey(user.id)) });
});
