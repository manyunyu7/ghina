"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireUser } from "@/lib/auth-helpers";
import { WALLET_TYPES, COLOR_PALETTE } from "@/lib/constants";
import { CURRENCIES } from "@/lib/utils";

const TYPE_VALUES = WALLET_TYPES.map((t) => t.value) as [string, ...string[]];

const walletSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(60),
  type: z.enum(TYPE_VALUES),
  balance: z.coerce.number().finite(),
  currency: z.enum(CURRENCIES as [string, ...string[]]),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/, "Invalid color"),
  icon: z.string().trim().min(1).max(40),
});

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

export async function updateWallet(formData: FormData): Promise<WalletActionResult> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing wallet id" };

  try {
    // Verify ownership before mutating.
    const existing = await prisma.wallet.findUnique({ where: { id }, select: { userId: true } });
    if (!existing || existing.userId !== user.id) {
      return { ok: false, error: "Wallet not found" };
    }

    const data = parse(formData, user.currency);
    await prisma.wallet.update({
      where: { id },
      data,
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      return { ok: false, error: err.issues[0]?.message ?? "Invalid data" };
    }
    return { ok: false, error: "Failed to update wallet" };
  }
  revalidate();
  return { ok: true };
}

export async function deleteWallet(formData: FormData): Promise<WalletActionResult> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing wallet id" };

  try {
    // Verify ownership before deleting; cascades transactions per schema.
    const existing = await prisma.wallet.findUnique({ where: { id }, select: { userId: true } });
    if (!existing || existing.userId !== user.id) {
      return { ok: false, error: "Wallet not found" };
    }
    await prisma.wallet.delete({ where: { id } });
  } catch {
    return { ok: false, error: "Failed to delete wallet" };
  }
  revalidate();
  return { ok: true };
}
