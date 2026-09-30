import http from "node:http";
import https from "node:https";
import { notFound } from "next/navigation";
import type { KillaMessage } from "@prisma/client";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { killaCommitSchema, killaSendSchema, killaWriteFileSchema } from "@/lib/schemas";

/**
 * Killa — the personal Claude agent served by killa-engine on the same host (docs/killa.md).
 * Server-only (node:http): the HTTP client for the engine contract, the email allowlist and
 * the chat log recorded in KillaMessage. Used by the web pages/actions and /api/mobile/killa.
 */

/** An expected Killa failure; `message` (Indonesian) is shown, `status` is the mobile HTTP status. */
export class KillaError extends Error {
  constructor(
    message: string,
    public status = 502,
  ) {
    super(message);
  }
}

// ---------- Access ----------

function allowedEmails(): Set<string> {
  return new Set(
    (process.env.KILLA_ALLOWED_EMAILS ?? "")
      .split(",")
      .map((e) => e.trim().toLowerCase())
      .filter(Boolean),
  );
}

/** Whether this email may use Killa (KILLA_ALLOWED_EMAILS; empty = nobody). */
export function isKillaAllowed(email: string | null | undefined): boolean {
  return !!email && allowedEmails().has(email.trim().toLowerCase());
}

/** requireUser() + allowlist; everyone else gets a 404 (the feature stays invisible). For pages. */
export async function requireKillaUser() {
  const user = await requireUser();
  if (!isKillaAllowed(user.email)) notFound();
  return user;
}

// ---------- killa-engine HTTP client ----------

/** POST /v1/chat can run for ~5 minutes; allow a margin on top. */
export const KILLA_CHAT_TIMEOUT_MS = 330_000;
const DEFAULT_TIMEOUT_MS = 20_000;
const MAX_RESPONSE_BYTES = 8 * 1024 * 1024;

type Query = Record<string, string | number | undefined>;

/**
 * One JSON request to killa-engine. Uses node:http instead of fetch: undici's fetch aborts
 * after 300 s without response headers, shorter than a long agent turn.
 */
function engineRequest<T>(
  method: "GET" | "POST" | "PUT" | "DELETE",
  path: string,
  opts: { query?: Query; body?: unknown; timeoutMs?: number } = {},
): Promise<T> {
  const base = process.env.KILLA_BASE_URL;
  const token = process.env.KILLA_TOKEN;
  if (!base || !token) return Promise.reject(new KillaError("Killa belum dikonfigurasi di server", 503));

  const url = new URL(path, base.endsWith("/") ? base : base + "/");
  for (const [k, v] of Object.entries(opts.query ?? {})) if (v !== undefined) url.searchParams.set(k, String(v));
  const payload = opts.body === undefined ? undefined : Buffer.from(JSON.stringify(opts.body));
  const lib = url.protocol === "https:" ? https : http;
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  return new Promise<T>((resolve, reject) => {
    const req = lib.request(
      url,
      {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
          ...(payload ? { "Content-Type": "application/json", "Content-Length": payload.length } : {}),
        },
        timeout: timeoutMs,
      },
      (res) => {
        const chunks: Buffer[] = [];
        let size = 0;
        res.on("data", (c: Buffer) => {
          size += c.length;
          if (size > MAX_RESPONSE_BYTES) {
            req.destroy(new KillaError("Respons Killa terlalu besar", 502));
            return;
          }
          chunks.push(c);
        });
        res.on("error", (e) => reject(e instanceof KillaError ? e : new KillaError("Koneksi ke Killa terputus", 502)));
        res.on("end", () => {
          const status = res.statusCode ?? 500;
          const text = Buffer.concat(chunks).toString("utf8");
          let json: unknown = null;
          try {
            json = text ? JSON.parse(text) : null;
          } catch {
            /* non-JSON body */
          }
          if (status >= 200 && status < 300) {
            if (json === null || typeof json !== "object") reject(new KillaError("Respons Killa tidak valid", 502));
            else resolve(json as T);
            return;
          }
          reject(engineError(status, json));
        });
      },
    );
    req.on("timeout", () => req.destroy(new KillaError("Killa tidak merespons (timeout)", 504)));
    req.on("error", (e) => {
      if (e instanceof KillaError) reject(e);
      else {
        console.error("[killa]", method, url.pathname, e.message);
        reject(new KillaError("Killa tidak bisa dihubungi", 502));
      }
    });
    if (payload) req.write(payload);
    req.end();
  });
}

function engineError(status: number, json: unknown): KillaError {
  const detail =
    json && typeof json === "object" && "error" in json && typeof json.error === "string" ? json.error : null;
  if (status === 413) return new KillaError("Berkas terlalu besar untuk ditampilkan", 413);
  if (status === 415) return new KillaError("Berkas bukan teks, tidak bisa ditampilkan", 415);
  if (status === 404) return new KillaError(detail ?? "Tidak ditemukan", 404);
  if (status === 400) return new KillaError(detail ?? "Permintaan tidak valid", 400);
  console.error("[killa] engine error", status, detail);
  return new KillaError(detail ? `Killa error: ${detail}` : `Killa error (${status})`, 502);
}

/** Workspace path from a client: relative, no NULs, bounded. "" = workspace root. */
export function cleanKillaPath(path: unknown): string {
  if (path == null || path === "") return "";
  if (typeof path !== "string" || path.length > 1024 || path.includes("\0")) throw new KillaError("Path tidak valid", 400);
  return path.replace(/^\/+/, "");
}

function clampLimit(v: unknown, def: number, max: number): number {
  const n = typeof v === "number" ? v : typeof v === "string" && v ? Number(v) : NaN;
  return Number.isFinite(n) ? Math.min(max, Math.max(1, Math.floor(n))) : def;
}

export type KillaChatReply = { reply: string; attachments?: string[] };
export type KillaFileEntry = { name: string; type: "file" | "dir"; size: number };
export type KillaFile = { path: string; content: string };
export type KillaCommit = { hash: string; date: string; author: string; subject: string };
export type KillaHistoryItem = { at: string; who: string; text: string };
export type KillaCommitResult = { ok: boolean; hash: string | null };

export const killaEngine = {
  chat: (chatKey: string, text: string, model?: string | null) =>
    engineRequest<KillaChatReply>("POST", "v1/chat", {
      body: { chatKey, text, ...(model ? { model } : {}) },
      timeoutMs: KILLA_CHAT_TIMEOUT_MS,
    }),
  newChat: (chatKey: string) => engineRequest<{ ok: boolean }>("POST", "v1/chat/new", { body: { chatKey } }),
  history: (chatKey: string, limit = 50) =>
    engineRequest<{ messages: KillaHistoryItem[] }>("GET", "v1/chat/history", { query: { chatKey, limit } }),
  async files(path: unknown): Promise<KillaFileEntry[]> {
    const res = await engineRequest<{ entries?: KillaFileEntry[] }>("GET", "v1/workspace/files", {
      query: { path: cleanKillaPath(path) },
    });
    return Array.isArray(res.entries) ? res.entries : [];
  },
  async file(path: unknown): Promise<KillaFile> {
    const p = cleanKillaPath(path);
    if (!p) throw new KillaError("Path tidak valid", 400);
    const res = await engineRequest<Partial<KillaFile>>("GET", "v1/workspace/file", { query: { path: p } });
    return { path: typeof res.path === "string" ? res.path : p, content: typeof res.content === "string" ? res.content : "" };
  },
  /** Create or overwrite a text file (PUT /v1/workspace/file). */
  async writeFile(input: unknown): Promise<{ ok: boolean; path: string }> {
    const { path, content } = killaWriteFileSchema.parse(input);
    const p = cleanKillaPath(path);
    if (!p) throw new KillaError("Path tidak valid", 400);
    const res = await engineRequest<{ ok?: boolean; path?: string }>("PUT", "v1/workspace/file", {
      body: { path: p, content },
    });
    return { ok: res.ok !== false, path: typeof res.path === "string" ? res.path : p };
  },
  /** Delete a file (DELETE /v1/workspace/file?path=). */
  async deleteFile(path: unknown): Promise<{ ok: boolean; path: string }> {
    const p = cleanKillaPath(path);
    if (!p) throw new KillaError("Path tidak valid", 400);
    const res = await engineRequest<{ ok?: boolean; path?: string }>("DELETE", "v1/workspace/file", { query: { path: p } });
    return { ok: res.ok !== false, path: typeof res.path === "string" ? res.path : p };
  },
  /** Commit the workspace (POST /v1/git/commit); `hash` null = nothing to commit. */
  async commit(input: unknown): Promise<KillaCommitResult> {
    const { message } = killaCommitSchema.parse(input ?? {});
    const res = await engineRequest<{ ok?: boolean; hash?: string | null }>("POST", "v1/git/commit", {
      body: message ? { message } : {},
    });
    return { ok: res.ok !== false, hash: typeof res.hash === "string" && res.hash ? res.hash : null };
  },
  async commits(limit?: unknown): Promise<KillaCommit[]> {
    const res = await engineRequest<{ commits?: KillaCommit[] }>("GET", "v1/git/log", {
      query: { limit: clampLimit(limit, 50, 200) },
    });
    return Array.isArray(res.commits) ? res.commits : [];
  },
};

// ---------- Chat log (KillaMessage) ----------

export const KILLA_PAGE_SIZE = 50;
export const KILLA_SESSION_DIVIDER = "Sesi baru";

export type KillaMessageDTO = {
  id: string;
  role: "user" | "assistant" | "system";
  body: string;
  model: string | null;
  createdAt: string;
};

export function toKillaDTO(m: KillaMessage): KillaMessageDTO {
  return {
    id: m.id,
    role: m.role as KillaMessageDTO["role"],
    body: m.body,
    model: m.model,
    createdAt: m.createdAt.toISOString(),
  };
}

/**
 * A page of the chat log, oldest first. `before` = id of the oldest message already shown
 * (cursor); `nextBefore` is the cursor for the page before this one (null = no more).
 */
export async function listKillaMessages(
  userId: string,
  opts: { before?: unknown; limit?: unknown } = {},
): Promise<{ messages: KillaMessageDTO[]; nextBefore: string | null }> {
  const take = clampLimit(opts.limit, KILLA_PAGE_SIZE, 200);
  const before = typeof opts.before === "string" && opts.before.length > 0 && opts.before.length <= 128 ? opts.before : null;
  if (before) {
    const cursor = await prisma.killaMessage.findFirst({ where: { id: before, userId }, select: { id: true } });
    if (!cursor) return { messages: [], nextBefore: null };
  }
  const rows = await prisma.killaMessage.findMany({
    where: { userId },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: take + 1,
    ...(before ? { cursor: { id: before }, skip: 1 } : {}),
  });
  const more = rows.length > take;
  const page = rows.slice(0, take);
  return { messages: page.reverse().map(toKillaDTO), nextBefore: more ? page[0].id : null };
}

/** Attachment paths from the engine are kept in the recorded reply as a short list. */
function replyBody(res: KillaChatReply): string {
  const reply = typeof res.reply === "string" ? res.reply : "";
  const files = Array.isArray(res.attachments) ? res.attachments.filter((a) => typeof a === "string") : [];
  if (!files.length) return reply || "(tanpa balasan)";
  return `${reply}\n\nLampiran:\n${files.map((f) => `- \`${f}\``).join("\n")}`.trim();
}

/**
 * Record the user's message, ask Killa (may take minutes) and record the reply. If Killa
 * fails the user message stays recorded and the KillaError is rethrown.
 */
export async function sendKillaMessage(userId: string, input: unknown) {
  const { text, model } = killaSendSchema.parse(input);
  const userMessage = await prisma.killaMessage.create({ data: { userId, role: "user", body: text, model } });
  const res = await killaEngine.chat(userId, text, model);
  const reply = await prisma.killaMessage.create({
    data: { userId, role: "assistant", body: replyBody(res), model },
  });
  return { userMessage: toKillaDTO(userMessage), reply: toKillaDTO(reply) };
}

/** Start a fresh engine session and record a divider in the log. */
export async function startKillaSession(userId: string) {
  await killaEngine.newChat(userId);
  const divider = await prisma.killaMessage.create({
    data: { userId, role: "system", body: KILLA_SESSION_DIVIDER },
  });
  return { divider: toKillaDTO(divider) };
}
