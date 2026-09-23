import type { NextRequest } from "next/server";
import { handle, HttpError, readJson, requireMobileUser } from "@/lib/mobile/http";
import { pull, push, pushBodySchema } from "@/lib/mobile/sync";

/** Pull: everything changed since the `since` cursor (ms since epoch; 0/absent = full pull). */
export const GET = handle(async (req: NextRequest) => {
  const user = await requireMobileUser(req);
  const raw = req.nextUrl.searchParams.get("since");
  const since = raw ? Number(raw) : 0;
  if (!Number.isFinite(since) || since < 0) throw new HttpError(400, "Invalid since cursor");
  return Response.json(await pull(user, Math.floor(since)));
});

/** Push: apply the client's outbox mutations in order. */
export const POST = handle(async (req: NextRequest) => {
  const user = await requireMobileUser(req);
  const body = await readJson(req, pushBodySchema);
  if (body.epoch !== undefined && body.epoch !== user.syncEpoch) {
    throw new HttpError(409, "Sync epoch changed — wipe local data and do a full pull", { epoch: user.syncEpoch });
  }
  return Response.json(await push(user, body.mutations));
});
