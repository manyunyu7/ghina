import type { User } from "@prisma/client";
import { handle, HttpError, requireMobileUser } from "@/lib/mobile/http";
import { isKillaAllowed, KillaError, type KillaMediaStream } from "@/lib/killa";

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

/**
 * Response for a file streamed from the engine (web and mobile media proxies). Images and
 * PDFs open inline; anything else downloads. Private cache; never sniffed or scripted.
 */
export function killaMediaResponse(path: string, media: KillaMediaStream): Response {
  const type = media.contentType;
  const inline = /^image\/(png|jpeg|gif|webp)\b/i.test(type) || /^application\/pdf\b/i.test(type);
  const name = (path.split("/").pop() || "berkas").replace(/[^\w.\-]+/g, "_").slice(0, 120) || "berkas";
  const headers = new Headers({
    "Content-Type": type,
    "Content-Disposition": `${inline ? "inline" : "attachment"}; filename="${name}"`,
    "Cache-Control": "private, max-age=3600",
    "X-Content-Type-Options": "nosniff",
  });
  // Nothing served here may script; PDFs are left out (Chrome's viewer refuses sandboxed PDFs).
  if (!/^application\/pdf\b/i.test(type)) headers.set("Content-Security-Policy", "sandbox; default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'");
  if (media.contentLength) headers.set("Content-Length", media.contentLength);
  return new Response(media.body, { headers });
}
