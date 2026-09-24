"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireUser } from "@/lib/auth-helpers";
import { COLOR_PALETTE } from "@/lib/constants";
import { walletSchema } from "@/lib/schemas";
import { deleteSynced } from "@/lib/sync-deletes";
import { adjustWalletBalance } from "@/lib/ledger";

export type WalletActionResult = { ok: boolean; error?: string };

function parse(formData: FormData, fallbackCurrency: string): z.infer<typeof walletSchema> {
  const colorRaw = String(formData.get("color") ?? "");
  const color = COLOR_PALETTE.includes(colorRaw) ? colorRaw : COLOR_PALETTE[0];
  const typeRaw = String(formData.get("type") ?? "");
  const currencyRaw = String(formData.get("currency") ?? fallbackCurrency) || fallbackCurrency;
  const iconRaw = String(formData.get("icon") ?? "").trim() || typeRaw;

  return walletSchema.parse({
    name: String(formData.get("name") ?? ""),
    type: typeRaw,
    balance: String(formData.get("balance") ?? "0") || "0",
    currency: currencyRaw,
    color,
    icon: iconRaw,
  });
}

function revalidate() {
  revalidatePath("/wallets");
  revalidatePath("/dashboard");
}

export async function createWallet(formData: FormData): Promise<WalletActionResult> {
  const user = await requireUser();
  try {
    const data = parse(formData, user.currency);
    await prisma.wallet.create({
      data: { ...data, userId: user.id },
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      return { ok: false, error: err.issues[0]?.message ?? "Invalid data" };
    }
    return { ok: false, error: "Failed to create wallet" };
  }
  revalidate();
  return { ok: true };
}

/**
 * Edit a wallet. The balance field is "Saldo sekarang": if it changed, a balance
 * `adjustment` transaction for the difference is recorded in the same DB transaction
 * (docs/balance-adjustment.md) — `Wallet.balance` is never overwritten directly.
 */
export async function updateWallet(formData: FormData): Promise<WalletActionResult> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing wallet id" };

  try {
    const { balance: target, ...fields } = parse(formData, user.currency);
    const userNote = String(formData.get("adjustmentNote") ?? "").trim();
    const dateRaw = String(formData.get("adjustmentDate") ?? "").trim();
    const date = parseAdjustmentDate(dateRaw);
    if (dateRaw && !date) return { ok: false, error: "Tanggal penyesuaian tidak valid" };

    const outcome = await prisma.$transaction(async (db) => {
      // Ownership check inside the transaction; the delta is computed from the live balance.
      const existing = await db.wallet.findUnique({ where: { id }, select: { userId: true } });
      if (!existing || existing.userId !== user.id) return "not-found" as const;

      await db.wallet.update({ where: { id }, data: { ...fields, editedAt: new Date() } });
      // Balance changes become an adjustment transaction — never a direct overwrite.
      await adjustWalletBalance(db, user.id, id, target, { currency: fields.currency, note: userNote, date });
      return "ok" as const;
    });
    if (outcome === "not-found") return { ok: false, error: "Wallet not found" };
  } catch (err) {
    if (err instanceof z.ZodError) {
      return { ok: false, error: err.issues[0]?.message ?? "Invalid data" };
    }
    return { ok: false, error: "Failed to update wallet" };
  }
  revalidate();
  revalidatePath("/transactions");
  return { ok: true };
}

/** "YYYY-MM-DD" (date input) → that day at the current local time; "" → null. */
function parseAdjustmentDate(v: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  if (!m) return null;
  const now = new Date();
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), now.getHours(), now.getMinutes(), now.getSeconds());
  return Number.isNaN(d.getTime()) ? null : d;
}

export async function deleteWallet(formData: FormData): Promise<WalletActionResult> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing wallet id" };

  try {
    // Verify ownership before deleting; its transactions are deleted too (see sync-deletes).
    const existing = await prisma.wallet.findUnique({ where: { id }, select: { userId: true } });
    if (!existing || existing.userId !== user.id) {
      return { ok: false, error: "Wallet not found" };
    }
    await deleteSynced(user.id, "wallets", id);
  } catch {
    return { ok: false, error: "Failed to delete wallet" };
  }
  revalidate();
  return { ok: true };
}
