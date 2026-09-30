import { killaChatKey, killaEngine } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";
import { readJson } from "@/lib/mobile/http";
import { killaCancelReminderSchema } from "@/lib/schemas";

/** `POST /api/mobile/killa/reminders/cancel {id}` → `{ ok }` — false when that reminder is already gone. */
export const POST = handleKilla(async (req: Request) => {
  const user = await requireKillaMobileUser(req);
  const { id } = await readJson(req, killaCancelReminderSchema);
  return Response.json(await killaEngine.cancelReminder(killaChatKey(user.id), id));
});
