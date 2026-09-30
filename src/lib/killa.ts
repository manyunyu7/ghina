import http from "node:http";
import https from "node:https";
import { Readable } from "node:stream";
import { timingSafeEqual } from "node:crypto";
import { notFound } from "next/navigation";
import type { KillaMessage } from "@prisma/client";
import { getCurrentUser, requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { sniffImageType } from "@/lib/photos";
import { saveUploadBytes } from "@/lib/uploads";
import {
  KILLA_MEDIA_MAX_BYTES,
  killaCommitSchema,
  killaMirrorSchema,
  killaSendSchema,
  killaSetModelSchema,
  killaWriteFileSchema,
} from "@/lib/schemas";

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

/**
 * Session user on the allowlist for web route handlers (no redirect): 401 without a
 * session, 404 when not allowlisted — thrown as KillaError so the route maps it to JSON.
 */
export async function requireKillaSessionUser() {
  const user = await getCurrentUser();
  if (!user) throw new KillaError("unauthorized", 401);
  if (!isKillaAllowed(user.email)) throw new KillaError("Tidak ditemukan", 404);
  return user;
}

/**
 * The single Killa owner account (first KILLA_ALLOWED_EMAILS entry that has a Ghina
 * user) — the mirror hook has no session, so its rows are filed under this user.
 */
export async function killaOwnerUserId(): Promise<string | null> {
  const emails = [...allowedEmails()];
  if (!emails.length) return null;
  const users = await prisma.user.findMany({ where: { email: { not: null } }, select: { id: true, email: true } });
  const byEmail = new Map(users.map((u) => [u.email!.trim().toLowerCase(), u.id]));
  for (const e of emails) {
    const id = byEmail.get(e);
    if (id) return id;
  }
  return null;
}

/** Digits of KILLA_WA_NUMBER, or null when unset. */
export function killaWaNumber(): string | null {
  const n = (process.env.KILLA_WA_NUMBER ?? "").replace(/\D/g, "");
  return n || null;
}

/**
 * Engine chatKey for a user. With KILLA_WA_NUMBER set it is `wa:<number>` — the owner's
 * own WhatsApp DM, one shared conversation across WA and Ghina (single-user feature);
 * otherwise the Ghina user id (a separate HTTP chat).
 */
export function killaChatKey(userId: string): string {
  const n = killaWaNumber();
  return n ? `wa:${n}` : userId;
}

/** Constant-time check of the mirror hook's `Authorization: Bearer <KILLA_MIRROR_TOKEN>`. */
export function isKillaMirrorAuthorized(header: string | null): boolean {
  const expected = process.env.KILLA_MIRROR_TOKEN ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(header ?? "");
  if (!expected || !m) return false;
  const a = Buffer.from(m[1].trim());
  const b = Buffer.from(expected);
  // Compare equal-length buffers so the timing does not depend on where they differ.
  const ok = timingSafeEqual(a.length === b.length ? a : b, b);
  return ok && a.length === b.length;
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
function engineUrl(path: string, query?: Query): { url: URL; token: string } {
  const base = process.env.KILLA_BASE_URL;
  const token = process.env.KILLA_TOKEN;
  if (!base || !token) throw new KillaError("Killa belum dikonfigurasi di server", 503);
  const url = new URL(path, base.endsWith("/") ? base : base + "/");
  for (const [k, v] of Object.entries(query ?? {})) if (v !== undefined) url.searchParams.set(k, String(v));
  return { url, token };
}

function engineRequest<T>(
  method: "GET" | "POST" | "PUT" | "DELETE",
  path: string,
  opts: { query?: Query; body?: unknown; timeoutMs?: number } = {},
): Promise<T> {
  let url: URL, token: string;
  try {
    ({ url, token } = engineUrl(path, opts.query));
  } catch (e) {
    return Promise.reject(e);
  }
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

/** A file streamed from the engine (GET /v1/media). */
export type KillaMediaStream = { body: ReadableStream<Uint8Array>; contentType: string; contentLength: string | null };

/**
 * GET /v1/media?path= as a stream (images, PDFs… the agent produced). Errors (400 bad
 * path, 404 missing, 413 > 15 MB) are read as JSON and thrown as KillaError.
 */
function engineMedia(path: string): Promise<KillaMediaStream> {
  let url: URL, token: string;
  try {
    ({ url, token } = engineUrl("v1/media", { path }));
  } catch (e) {
    return Promise.reject(e);
  }
  const lib = url.protocol === "https:" ? https : http;
  return new Promise((resolve, reject) => {
    const req = lib.request(
      url,
      { method: "GET", headers: { Authorization: `Bearer ${token}` }, timeout: DEFAULT_TIMEOUT_MS },
      (res) => {
        const status = res.statusCode ?? 500;
        if (status >= 200 && status < 300) {
          resolve({
            body: Readable.toWeb(res) as ReadableStream<Uint8Array>,
            contentType: res.headers["content-type"] ?? "application/octet-stream",
            contentLength: res.headers["content-length"] ?? null,
          });
          return;
        }
        const chunks: Buffer[] = [];
        res.on("data", (c: Buffer) => {
          if (chunks.length < 64) chunks.push(c);
        });
        res.on("error", () => reject(new KillaError("Koneksi ke Killa terputus", 502)));
        res.on("end", () => {
          let json: unknown = null;
          try {
            json = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          } catch {
            /* non-JSON body */
          }
          reject(status === 413 ? new KillaError("Berkas terlalu besar (maks 15 MB)", 413) : engineError(status, json));
        });
      },
    );
    req.on("timeout", () => req.destroy(new KillaError("Killa tidak merespons (timeout)", 504)));
    req.on("error", (e) => {
      if (e instanceof KillaError) reject(e);
      else {
        console.error("[killa] GET /v1/media", e.message);
        reject(new KillaError("Killa tidak bisa dihubungi", 502));
      }
    });
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
export type KillaEngineMedia = { name?: string; mimeType: string; dataBase64: string };
export type KillaModelState = { model: string | null; options: string[] };
export type KillaReminder ={ id: number; spec: string; text: string; nextAt: number };
export type KillaUsageTotals = {
  turns: number;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheCreationTokens: number;
  costUsd: number;
};
export type KillaUsageDay = KillaUsageTotals & { date: string };
export type KillaUsage = {
  since: number;
  days: KillaUsageDay[];
  byModel: Record<string, KillaUsageTotals>;
  total: KillaUsageTotals;
};

const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
function usageTotals(v: unknown): KillaUsageTotals {
  const o = (v && typeof v === "object" ? v : {}) as Record<string, unknown>;
  return {
    turns: num(o.turns),
    inputTokens: num(o.inputTokens),
    outputTokens: num(o.outputTokens),
    cacheReadTokens: num(o.cacheReadTokens),
    cacheCreationTokens: num(o.cacheCreationTokens),
    costUsd: num(o.costUsd),
  };
}

export const killaEngine = {
  chat: (chatKey: string, text: string, model?: string | null, media?: KillaEngineMedia[]) =>
    engineRequest<KillaChatReply>("POST", "v1/chat", {
      body: { chatKey, text, ...(model ? { model } : {}), ...(media?.length ? { media } : {}) },
      timeoutMs: KILLA_CHAT_TIMEOUT_MS,
    }),
  /**
   * The chat's persisted model (GET /v1/model) — same store as WhatsApp's `/model`;
   * `model` null = engine default, `options` = what the engine accepts.
   */
  async getModel(chatKey: string): Promise<KillaModelState> {
    const res = await engineRequest<{ model?: unknown; options?: unknown }>("GET", "v1/model", { query: { chatKey } });
    return {
      model: typeof res.model === "string" && res.model && res.model !== "default" ? res.model : null,
      options: Array.isArray(res.options) ? res.options.filter((o): o is string => typeof o === "string" && !!o) : [],
    };
  },
  /** Persist the chat's model (POST /v1/model); "default" clears it. Applies to WA too. */
  async setModel(chatKey: string, input: unknown): Promise<{ ok: boolean; model: string | null }> {
    const { model } = killaSetModelSchema.parse(input);
    const res = await engineRequest<{ ok?: boolean; model?: unknown }>("POST", "v1/model", { body: { chatKey, model } });
    const saved = typeof res.model === "string" && res.model && res.model !== "default" ? res.model : null;
    return { ok: res.ok !== false, model: saved };
  },
  /** Scheduled reminders of the chat, soonest first (GET /v1/reminders). */
  async reminders(chatKey: string): Promise<KillaReminder[]> {
    const res = await engineRequest<{ reminders?: unknown[] }>("GET", "v1/reminders", { query: { chatKey } });
    return (Array.isArray(res.reminders) ? res.reminders : [])
      .filter((r): r is Record<string, unknown> => !!r && typeof r === "object")
      .map((r) => ({
        id: num(r.id),
        spec: typeof r.spec === "string" ? r.spec : "",
        text: typeof r.text === "string" ? r.text : "",
        nextAt: num(r.nextAt),
      }))
      .filter((r) => r.id > 0);
  },
  /** Cancel a reminder; `ok` false = no such reminder in that chat (already fired/cancelled). */
  async cancelReminder(chatKey: string, id: number): Promise<{ ok: boolean }> {
    const res = await engineRequest<{ ok?: boolean }>("POST", "v1/reminders/cancel", { body: { chatKey, id } });
    return { ok: res.ok === true };
  },
  /** Token/cost accounting of every agent run over the last `days` local days (≤ 90). */
  async usage(days?: unknown): Promise<KillaUsage> {
    const res = await engineRequest<Record<string, unknown>>("GET", "v1/usage", {
      query: { days: clampLimit(days, 30, 90) },
    });
    const byModel: Record<string, KillaUsageTotals> = {};
    if (res.byModel && typeof res.byModel === "object") {
      for (const [k, v] of Object.entries(res.byModel)) byModel[k] = usageTotals(v);
    }
    return {
      since: num(res.since),
      days: (Array.isArray(res.days) ? res.days : []).map((d) => ({
        ...usageTotals(d),
        date: d && typeof d === "object" && typeof (d as { date?: unknown }).date === "string" ? (d as { date: string }).date : "",
      })),
      byModel,
      total: usageTotals(res.total),
    };
  },
  /** Stream a file the agent produced (GET /v1/media?path=). */
  media(path: unknown): Promise<KillaMediaStream> {
    if (typeof path !== "string" || !path || path.length > 1024 || path.includes("\0")) {
      return Promise.reject(new KillaError("Path tidak valid", 400));
    }
    return engineMedia(path);
  },
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

/**
 * A file on a message. `source` "upload" = a Ghina /uploads URL (the user's own sent
 * file; `path` is directly servable), "engine" = a path on the engine host (an agent
 * output; serve it via /api/killa/media or /api/mobile/killa/media `?path=`).
 */
export type KillaAttachment = { path: string; name: string; kind: "image" | "file"; source: "upload" | "engine" };

export type KillaMessageDTO = {
  id: string;
  role: "user" | "assistant" | "system";
  body: string;
  model: string | null;
  channel: "app" | "wa";
  attachments: KillaAttachment[];
  createdAt: string;
};

const IMAGE_EXT_RE = /\.(jpe?g|png|gif|webp)$/i;

export function parseKillaAttachments(stored: string | null | undefined): KillaAttachment[] {
  if (!stored) return [];
  let list: unknown;
  try {
    list = JSON.parse(stored);
  } catch {
    return [];
  }
  if (!Array.isArray(list)) return [];
  return list
    .filter((p): p is string => typeof p === "string" && p.length > 0 && p.length <= 1024)
    .map((path) => ({
      path,
      name: path.split("/").pop() || path,
      kind: IMAGE_EXT_RE.test(path) ? "image" : "file",
      source: path.startsWith("/uploads/") ? "upload" : "engine",
    }));
}

export function toKillaDTO(m: KillaMessage): KillaMessageDTO {
  return {
    id: m.id,
    role: m.role as KillaMessageDTO["role"],
    body: m.body,
    model: m.model,
    channel: m.channel === "wa" ? "wa" : "app",
    attachments: parseKillaAttachments(m.attachments),
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

/** Engine-accepted attachment types by sniffed extension. */
const KILLA_MEDIA_MIME: Record<string, string> = {
  jpg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  gif: "image/gif",
  pdf: "application/pdf",
};

/** The attachment type by its first bytes (the client MIME type/name are not trusted). */
function sniffKillaMedia(bytes: Buffer): string | null {
  const img = sniffImageType(bytes);
  if (img === "heic" || img === "heif") throw new KillaError("HEIC belum didukung — kirim JPEG/PNG", 415);
  if (img) return img;
  if (bytes.subarray(0, 5).toString("latin1") === "%PDF-") return "pdf";
  return null;
}

const BASE64_RE = /^[A-Za-z0-9+/]*={0,2}$/;

/**
 * Record the user's message (its files saved to /uploads), ask Killa with the files as
 * base64 `media` (may take minutes) and record the reply with the engine's attachment
 * paths. If Killa fails the user message stays recorded and the KillaError is rethrown.
 */
export async function sendKillaMessage(userId: string, input: unknown) {
  const { text, model: turnModel, media } = killaSendSchema.parse(input);
  // No per-turn model (the web app never sends one) → the engine uses the chat's persisted
  // model; look it up only to label the recorded messages (best-effort).
  const model =
    turnModel ?? (await killaEngine.getModel(killaChatKey(userId)).then((m) => m.model, () => null));

  const files = media.map((m, i) => {
    const b64 = m.dataBase64.replace(/^data:[^,]*,/, "").replace(/\s+/g, "");
    if (!BASE64_RE.test(b64)) throw new KillaError("Lampiran tidak valid (base64)", 400);
    const bytes = Buffer.from(b64, "base64");
    if (bytes.length === 0) throw new KillaError("Lampiran kosong", 400);
    if (bytes.length > KILLA_MEDIA_MAX_BYTES) throw new KillaError("Lampiran terlalu besar (maks 8 MB)", 413);
    const ext = sniffKillaMedia(bytes);
    if (!ext) throw new KillaError("Lampiran harus gambar (JPEG, PNG, WebP, GIF) atau PDF", 415);
    const base = (m.name ?? "").split(/[\\/]/).pop()?.replace(/[^\w.\- ]+/g, "_").slice(0, 100) || `lampiran-${i + 1}`;
    const name = base.toLowerCase().endsWith(`.${ext}`) || (ext === "jpg" && /\.jpeg$/i.test(base)) ? base : `${base}.${ext}`;
    return { bytes, ext, name };
  });

  const urls: string[] = [];
  for (const f of files) urls.push(await saveUploadBytes(f.bytes, f.ext));

  const userMessage = await prisma.killaMessage.create({
    data: { userId, role: "user", body: text, model, channel: "app", attachments: urls.length ? JSON.stringify(urls) : null },
  });
  const res = await killaEngine.chat(
    killaChatKey(userId),
    text,
    turnModel,
    files.map((f) => ({ name: f.name, mimeType: KILLA_MEDIA_MIME[f.ext], dataBase64: f.bytes.toString("base64") })),
  );
  const reply = typeof res.reply === "string" ? res.reply : "";
  const outs = Array.isArray(res.attachments) ? res.attachments.filter((a) => typeof a === "string" && a) : [];
  const replyMessage = await prisma.killaMessage.create({
    data: {
      userId,
      role: "assistant",
      body: reply || (outs.length ? "" : "(tanpa balasan)"),
      model,
      channel: "app",
      attachments: outs.length ? JSON.stringify(outs) : null,
    },
  });
  return { userMessage: toKillaDTO(userMessage), reply: toKillaDTO(replyMessage) };
}

/** Start a fresh engine session and record a divider in the log. */
export async function startKillaSession(userId: string) {
  await killaEngine.newChat(killaChatKey(userId));
  const divider = await prisma.killaMessage.create({
    data: { userId, role: "system", body: KILLA_SESSION_DIVIDER },
  });
  return { divider: toKillaDTO(divider) };
}

/**
 * Store the WhatsApp side of the shared conversation (engine mirror hook). Rows go to
 * the owner account with channel "wa"; exact (role, text, at) duplicates are skipped.
 */
export async function ingestKillaMirror(input: unknown): Promise<{ inserted: number; skipped: number }> {
  const body = killaMirrorSchema.parse(input);
  const wa = killaWaNumber();
  if (wa && body.number !== wa) throw new KillaError("number bukan KILLA_WA_NUMBER", 400);
  const userId = await killaOwnerUserId();
  if (!userId) throw new KillaError("Pemilik Killa tidak ditemukan (KILLA_ALLOWED_EMAILS)", 503);

  let inserted = 0;
  let skipped = 0;
  for (const m of body.messages) {
    const createdAt = new Date(m.at);
    if (Number.isNaN(createdAt.getTime())) {
      skipped++;
      continue;
    }
    const dup = await prisma.killaMessage.findFirst({
      where: { userId, role: m.role, body: m.text, createdAt },
      select: { id: true },
    });
    if (dup) {
      skipped++;
      continue;
    }
    await prisma.killaMessage.create({ data: { userId, role: m.role, body: m.text, channel: "wa", createdAt } });
    inserted++;
  }
  return { inserted, skipped };
}
