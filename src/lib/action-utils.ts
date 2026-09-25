import { z } from "zod";
import { NoteError } from "@/lib/notes-server";
import { ContentError } from "@/lib/content-server";
import { TaskError } from "@/lib/tasks-server";
import { HabitError } from "@/lib/habits-server";
import { InvestmentError } from "@/lib/investments-server";

/**
 * Helpers for server actions that return `{ ok: true, … } | { ok: false, error }`
 * (notes, content). Not a "use server" module — imported by the action files.
 */

export type ActionResult<T extends object = object> = ({ ok: true } & T) | { ok: false; error: string };

/** An expected failure; its message (Indonesian) is shown to the user. */
export class UserError extends Error {}

/** Map expected failures to `{ok:false,error}`; unexpected ones are logged and generic. */
export async function runAction<T extends object>(tag: string, fn: () => Promise<T>): Promise<ActionResult<T>> {
  try {
    return { ok: true, ...(await fn()) };
  } catch (e) {
    if (e instanceof z.ZodError) return { ok: false, error: e.issues[0]?.message ?? "Data tidak valid" };
    if (
      e instanceof UserError ||
      e instanceof NoteError ||
      e instanceof ContentError ||
      e instanceof TaskError ||
      e instanceof HabitError ||
      e instanceof InvestmentError
    )
      return { ok: false, error: e.message };
    console.error(`[${tag} action]`, e);
    return { ok: false, error: "Terjadi kesalahan, coba lagi" };
  }
}

/**
 * Server-action arguments arrive via React's reply decoding, so a crafted request can
 * pass an object where a string id is expected — which Prisma would read as a filter.
 * Reject anything but a plain id string up front.
 */
export function assertId(id: unknown, notFound: string): asserts id is string {
  if (typeof id !== "string" || id.length === 0 || id.length > 128) throw new UserError(notFound);
}

export function assertIds(ids: unknown, notFound: string): asserts ids is string[] {
  if (!Array.isArray(ids) || ids.length > 1000) throw new UserError(notFound);
  for (const id of ids) assertId(id, notFound);
}

/** A plain object argument (not an array/null/primitive). */
export function assertObject(v: unknown, what = "Data"): asserts v is Record<string, unknown> {
  if (typeof v !== "object" || v === null || Array.isArray(v)) throw new UserError(`${what} tidak valid`);
}

/** Copy the listed keys that are present and not undefined. */
export function pick<T extends object>(src: T | null | undefined, keys: readonly string[]): Partial<T> {
  const out: Record<string, unknown> = {};
  if (!src || typeof src !== "object") return out as Partial<T>;
  for (const k of keys) {
    const v = (src as Record<string, unknown>)[k];
    if (k in src && v !== undefined) out[k] = v;
  }
  return out as Partial<T>;
}

/** Files of a FormData field (empty entries ignored). */
export function formFiles(fd: FormData, field: string): File[] {
  return fd.getAll(field).filter((f): f is File => f instanceof File && f.size > 0);
}
