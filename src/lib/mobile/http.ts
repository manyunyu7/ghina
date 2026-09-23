import type { User } from "@prisma/client";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import { verifyMobileToken } from "@/lib/mobile/token";

/** Error with an HTTP status; rendered as `{"error": message}` by `handle`. */
export class HttpError extends Error {
  constructor(
    public status: number,
    message: string,
    public extra?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export function jsonError(status: number, error: string, extra?: Record<string, unknown>) {
  return Response.json({ error, ...extra }, { status });
}

/** Wrap a route handler so every failure becomes a JSON `{error}` response. */
export function handle<A extends unknown[]>(fn: (...args: A) => Promise<Response>) {
  return async (...args: A): Promise<Response> => {
    try {
      return await fn(...args);
    } catch (err) {
      if (err instanceof HttpError) return jsonError(err.status, err.message, err.extra);
      if (err instanceof z.ZodError) return jsonError(400, err.issues[0]?.message ?? "Invalid input");
      console.error("[mobile api]", err);
      return jsonError(500, "Internal server error");
    }
  };
}

/** Parse a JSON body with a zod schema (400 on malformed JSON or invalid data). */
export async function readJson<T extends z.ZodType>(req: Request, schema: T): Promise<z.infer<T>> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw new HttpError(400, "Invalid JSON body");
  }
  return schema.parse(body);
}

/** The user behind the request's bearer token; 401 otherwise. */
export async function requireMobileUser(req: Request): Promise<User> {
  const header = req.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  const userId = match ? await verifyMobileToken(match[1].trim()) : null;
  const user = userId ? await prisma.user.findUnique({ where: { id: userId } }) : null;
  if (!user) throw new HttpError(401, "unauthorized");
  return user;
}
