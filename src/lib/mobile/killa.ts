import type { User } from "@prisma/client";
import { handle, HttpError, requireMobileUser } from "@/lib/mobile/http";
import { isKillaAllowed, KillaError } from "@/lib/killa";

/** Bearer user who is also on KILLA_ALLOWED_EMAILS; 401 / 403 otherwise (docs/killa.md). */
export async function requireKillaMobileUser(req: Request): Promise<User> {
  const user = await requireMobileUser(req);
  if (!isKillaAllowed(user.email)) throw new HttpError(403, "forbidden");
  return user;
}

/** `handle` that also maps KillaError to `{error}` with its status (502/504 engine, 413/415 file…). */
export function handleKilla<A extends unknown[]>(fn: (...args: A) => Promise<Response>) {
  return handle(async (...args: A) => {
    try {
      return await fn(...args);
    } catch (e) {
      if (e instanceof KillaError) throw new HttpError(e.status, e.message);
      throw e;
    }
  });
}
