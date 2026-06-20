"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";

const schema = z.object({
  type: z.enum(["expense", "income"]),
  amount: z.coerce.number().positive("Amount must be greater than 0"),
  note: z.string().trim().max(200).optional().nullable(),
  date: z.coerce.date(),
  categoryId: z.string().optional().nullable(),
  walletId: z.string().optional().nullable(),
});

type Result = { ok: boolean; error?: string };

function parse(formData: FormData) {
  const emptyToNull = (v: FormDataEntryValue | null) => (v === null || v === "" ? null : String(v));
  return schema.safeParse({
    type: formData.get("type") || "expense",
    amount: formData.get("amount"),
    note: emptyToNull(formData.get("note")),
    date: formData.get("date"),
    categoryId: emptyToNull(formData.get("categoryId")),
    walletId: emptyToNull(formData.get("walletId")),
  });
}

/** Confirm referenced category/wallet belong to the user (guards against forged ids). */
async function assertOwnership(userId: string, categoryId?: string | null, walletId?: string | null) {
  if (categoryId) {
    const c = await prisma.category.findFirst({ where: { id: categoryId, userId }, select: { id: true } });
    if (!c) throw new Error("Category not found");
  }
  if (walletId) {
    const w = await prisma.wallet.findFirst({ where: { id: walletId, userId }, select: { id: true } });
    if (!w) throw new Error("Wallet not found");
  }
}

function revalidate() {
  revalidatePath("/forecast");
  revalidatePath("/dashboard");
}

export async function createPlanned(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const parsed = parse(formData);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  const d = parsed.data;

  try {
    await assertOwnership(user.id, d.categoryId, d.walletId);
    await prisma.plannedTransaction.create({
      data: {
        userId: user.id,
        type: d.type,
        amount: d.amount,
        note: d.note ?? null,
        date: d.date,
        categoryId: d.categoryId ?? null,
        walletId: d.walletId ?? null,
      },
    });
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Failed to create" };
  }
  revalidate();
  return { ok: true };
}

export async function updatePlanned(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing id" };

  const parsed = parse(formData);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  const d = parsed.data;

  const existing = await prisma.plannedTransaction.findFirst({ where: { id, userId: user.id }, select: { id: true } });
  if (!existing) return { ok: false, error: "Planned item not found" };

  try {
    await assertOwnership(user.id, d.categoryId, d.walletId);
    await prisma.plannedTransaction.update({
      where: { id },
      data: {
        type: d.type,
        amount: d.amount,
        note: d.note ?? null,
        date: d.date,
        categoryId: d.categoryId ?? null,
        walletId: d.walletId ?? null,
      },
    });
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Failed to update" };
  }
  revalidate();
  return { ok: true };
}

export async function deletePlanned(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  const existing = await prisma.plannedTransaction.findFirst({ where: { id, userId: user.id }, select: { id: true } });
  if (!existing) return { ok: false, error: "Planned item not found" };

  await prisma.plannedTransaction.delete({ where: { id } });
  revalidate();
  return { ok: true };
}

/**
 * Turn a planned item into a real transaction: creates the Transaction, moves the
 * wallet balance (debit for expense, credit for income), and removes the plan so it
 * can't be double-counted. Mirrors `markSubscriptionPaid`.
 */
export async function convertPlanned(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");

  const item = await prisma.plannedTransaction.findFirst({ where: { id, userId: user.id } });
  if (!item) return { ok: false, error: "Planned item not found" };

  // Need a wallet to move money on. Prefer the item's tagged wallet, else the first one.
  let walletId = item.walletId;
  if (!walletId) {
    const firstWallet = await prisma.wallet.findFirst({
      where: { userId: user.id, archived: false },
      orderBy: { createdAt: "asc" },
      select: { id: true },
    });
    if (!firstWallet) {
      return { ok: false, error: "Create a wallet first, or set a wallet on this item." };
    }
    walletId = firstWallet.id;
  }

  const balanceChange = item.type === "expense" ? { decrement: item.amount } : { increment: item.amount };

  try {
    await prisma.$transaction([
      prisma.transaction.create({
        data: {
          userId: user.id,
          walletId,
          categoryId: item.categoryId,
          type: item.type,
          amount: item.amount,
          note: item.note,
          date: item.date,
        },
      }),
      prisma.wallet.update({ where: { id: walletId }, data: { balance: balanceChange } }),
      prisma.plannedTransaction.delete({ where: { id: item.id } }),
    ]);
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Failed to convert" };
  }

  revalidatePath("/forecast");
  revalidatePath("/dashboard");
  revalidatePath("/transactions");
  revalidatePath("/wallets");
  return { ok: true };
}

export async function togglePlannedDone(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  const existing = await prisma.plannedTransaction.findFirst({ where: { id, userId: user.id }, select: { done: true } });
  if (!existing) return { ok: false, error: "Planned item not found" };

  await prisma.plannedTransaction.update({ where: { id }, data: { done: !existing.done } });
  revalidate();
  return { ok: true };
}
