"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { runAction, UserError, type ActionResult } from "@/lib/action-utils";
import {
  isKillaAllowed,
  killaChatKey,
  killaEngine,
  listKillaMessages,
  sendKillaMessage,
  startKillaSession,
  type KillaMessageDTO,
} from "@/lib/killa";
import { KILLA_MEDIA_MAX_BYTES, KILLA_MEDIA_MAX_FILES, killaCancelReminderSchema } from "@/lib/schemas";

/**
 * Server actions of the Killa chat (docs/killa.md). Results `{ ok: true, … } | { ok: false, error }`.
 * Every message and reply is recorded in KillaMessage; the page is revalidated even when
 * Killa fails, since the user's message is already stored.
 */

/** Allowlist check, inside runAction (requireUser itself must stay outside: it redirects). */
function killaUserId(user: { id: string; email: string | null }) {
  if (!isKillaAllowed(user.email)) throw new UserError("Tidak diizinkan");
  return user.id;
}

/**
 * Send a message and wait for Killa's reply (can take minutes). FormData: `text`,
 * `files` (≤ 3 images/PDF, ≤ 8 MB each) — the files are stored in /uploads
 * and passed to the engine as base64 media.
 */
export async function sendKillaChat(form: FormData): Promise<
  ActionResult<{ userMessage: KillaMessageDTO; reply: KillaMessageDTO }>
> {
  const user = await requireUser();
  const res = await runAction("killa", async () => {
    const userId = killaUserId(user);
    if (!(form instanceof FormData)) throw new UserError("Data tidak valid");
    const files = form.getAll("files").filter((f): f is File => f instanceof File && f.size > 0);
    if (files.length > KILLA_MEDIA_MAX_FILES) throw new UserError(`Maksimal ${KILLA_MEDIA_MAX_FILES} lampiran`);
    if (files.some((f) => f.size > KILLA_MEDIA_MAX_BYTES)) throw new UserError("Lampiran terlalu besar (maks 8 MB)");
    const media = await Promise.all(
      files.map(async (f) => ({ name: f.name, dataBase64: Buffer.from(await f.arrayBuffer()).toString("base64") })),
    );
    const text = form.get("text");
    // No per-turn model: the engine uses the chat's persisted one (setKillaModel).
    return sendKillaMessage(userId, { text: typeof text === "string" ? text : "", media });
  });
  revalidatePath("/killa");
  return res;
}

/**
 * Persist the chat model engine-side (POST /v1/model) — shared with WhatsApp's `/model`;
 * "default" clears it. `model` null = engine default.
 */
export async function setKillaModel(model: string): Promise<ActionResult<{ model: string | null }>> {
  const user = await requireUser();
  return runAction("killa", async () => {
    const userId = killaUserId(user);
    const res = await killaEngine.setModel(killaChatKey(userId), { model });
    return { model: res.model };
  });
}

/** Start a new Killa session (adds a "Sesi baru" divider to the log). */
export async function newKillaSession(): Promise<ActionResult<{ divider: KillaMessageDTO }>> {
  const user = await requireUser();
  const res = await runAction("killa", async () => startKillaSession(killaUserId(user)));
  if (res.ok) revalidatePath("/killa");
  return res;
}

/** Older messages for "Muat pesan lama" (cursor = oldest id shown). */
export async function loadOlderKillaMessages(
  before: string,
): Promise<ActionResult<{ messages: KillaMessageDTO[]; nextBefore: string | null }>> {
  const user = await requireUser();
  return runAction("killa", async () => listKillaMessages(killaUserId(user), { before }));
}

/** Save a workspace text file (PUT /v1/workspace/file). */
export async function saveKillaFile(input: { path: string; content: string }): Promise<ActionResult<{ path: string }>> {
  const user = await requireUser();
  const res = await runAction("killa", async () => {
    killaUserId(user);
    const saved = await killaEngine.writeFile(input);
    return { path: saved.path };
  });
  if (res.ok) revalidatePath("/killa/files");
  return res;
}

/** Commit the workspace (POST /v1/git/commit); `hash` null = nothing to commit. */
export async function commitKillaWorkspace(message?: string | null): Promise<ActionResult<{ hash: string | null }>> {
  const user = await requireUser();
  const res = await runAction("killa", async () => {
    killaUserId(user);
    const { hash } = await killaEngine.commit({ message: typeof message === "string" ? message : null });
    return { hash };
  });
  if (res.ok) revalidatePath("/killa/commits");
  return res;
}

/** Cancel one of Killa's reminders (POST /v1/reminders/cancel); `cancelled` false = already gone. */
export async function cancelKillaReminder(id: number): Promise<ActionResult<{ cancelled: boolean }>> {
  const user = await requireUser();
  const res = await runAction("killa", async () => {
    const userId = killaUserId(user);
    const parsed = killaCancelReminderSchema.parse({ id });
    const { ok } = await killaEngine.cancelReminder(killaChatKey(userId), parsed.id);
    return { cancelled: ok };
  });
  if (res.ok) revalidatePath("/killa/reminders");
  return res;
}
