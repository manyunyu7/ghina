import { startKillaSession } from "@/lib/killa";
import { handleKilla, requireKillaMobileUser } from "@/lib/mobile/killa";

/** `POST /api/mobile/killa/chat/new` → `{ divider }`: fresh Killa session + "Sesi baru" divider in the log. */
export const POST = handleKilla(async (req: Request) => {
  const user = await requireKillaMobileUser(req);
  return Response.json(await startKillaSession(user.id));
});
