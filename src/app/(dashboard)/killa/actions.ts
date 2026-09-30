"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { runAction, UserError, type ActionResult } from "@/lib/action-utils";
import {
  isKillaAllowed,
  killaEngine,
  listKillaMessages,
  sendKillaMessage,
  startKillaSession,
  type KillaMessageDTO,
} from "@/lib/killa";
import type { KillaModel } from "@/lib/schemas";

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

/** Send a message and wait for Killa's reply (can take minutes). */
export async function sendKillaChat(input: { text: string; model?: KillaModel }): Promise<
  ActionResult<{ userMessage: KillaMessageDTO; reply: KillaMessageDTO }>
> {
  const user = await requireUser();
  const res = await runAction("killa", async () => sendKillaMessage(killaUserId(user), input));
  revalidatePath("/killa");
  return res;
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
