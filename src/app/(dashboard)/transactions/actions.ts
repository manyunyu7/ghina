"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import type { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { requireUser } from "@/lib/auth-helpers";

function revalidateAll() {
  revalidatePath("/transactions");
  revalidatePath("/dashboard");
  revalidatePath("/wallets");
}

const baseSchema = z.object({
  type: z.enum(["expense", "income", "transfer"]),
  amount: z.coerce.number().positive("Amount must be greater than 0"),
  walletId: z.string().min(1, "Wallet is required"),
  toWalletId: z
    .string()
    .optional()
    .transform((v) => (v && v.length > 0 ? v : null)),
  categoryId: z
    .string()
    .optional()
    .transform((v) => (v && v.length > 0 ? v : null)),
  note: z
    .string()
    .optional()
    .transform((v) => (v && v.trim().length > 0 ? v.trim() : null)),
  date: z.coerce.date(),
});

type TxShape = { type: string; amount: number; walletId: string; toWalletId: string | null };

/**
 * Net effect of a transaction on wallet balances, keyed by walletId.
 * income: +amount to wallet · expense: −amount · transfer: −amount from source, +amount to destination.
 */
function effects(t: TxShape): Record<string, number> {
  const e: Record<string, number> = {};
  const add = (id: string, d: number) => {
    e[id] = (e[id] ?? 0) + d;
  };
  if (t.type === "income") add(t.walletId, t.amount);
  else if (t.type === "expense") add(t.walletId, -t.amount);
  else if (t.type === "transfer" && t.toWalletId) {
    add(t.walletId, -t.amount);
    add(t.toWalletId, t.amount);
  }
  return e;
}

function mergeDeltas(...maps: Record<string, number>[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const m of maps) for (const [id, d] of Object.entries(m)) out[id] = (out[id] ?? 0) + d;
  return out;
}

function balanceOps(deltas: Record<string, number>): Prisma.PrismaPromise<unknown>[] {
  return Object.entries(deltas)
    .filter(([, d]) => d !== 0)
    .map(([id, d]) => prisma.wallet.update({ where: { id }, data: { balance: { increment: d } } }));
}

/** Validate ownership of wallets/category and normalize a transfer's fields. */
async function validateRefs(
  userId: string,
  p: z.infer<typeof baseSchema>,
): Promise<{ toWalletId: string | null; categoryId: string | null }> {
  const wallet = await prisma.wallet.findFirst({ where: { id: p.walletId, userId }, select: { id: true } });
  if (!wallet) throw new Error("Wallet not found");

  if (p.type === "transfer") {
    if (!p.toWalletId) throw new Error("Choose a destination wallet");
    if (p.toWalletId === p.walletId) throw new Error("Source and destination must differ");
    const dest = await prisma.wallet.findFirst({ where: { id: p.toWalletId, userId }, select: { id: true } });
    if (!dest) throw new Error("Destination wallet not found");
    // Transfers carry no category.
    return { toWalletId: p.toWalletId, categoryId: null };
  }

  if (p.categoryId) {
    const category = await prisma.category.findFirst({ where: { id: p.categoryId, userId }, select: { id: true } });
    if (!category) throw new Error("Category not found");
  }
  return { toWalletId: null, categoryId: p.categoryId };
}

function read(formData: FormData) {
  return baseSchema.parse({
    type: formData.get("type"),
    amount: formData.get("amount"),
    walletId: formData.get("walletId"),
    toWalletId: formData.get("toWalletId") ?? undefined,
    categoryId: formData.get("categoryId") ?? undefined,
    note: formData.get("note") ?? undefined,
    date: formData.get("date"),
  });
}

export async function createTransaction(formData: FormData) {
  const user = await requireUser();
  const parsed = read(formData);
  const { toWalletId, categoryId } = await validateRefs(user.id, parsed);

  const deltas = effects({ type: parsed.type, amount: parsed.amount, walletId: parsed.walletId, toWalletId });

  await prisma.$transaction([
    prisma.transaction.create({
      data: {
        userId: user.id,
        walletId: parsed.walletId,
        toWalletId,
        categoryId,
        type: parsed.type,
        amount: parsed.amount,
        note: parsed.note,
        date: parsed.date,
      },
    }),
    ...balanceOps(deltas),
  ]);

  revalidateAll();
}

export async function updateTransaction(formData: FormData) {
  const user = await requireUser();
  const id = formData.get("id");
  if (typeof id !== "string" || id.length === 0) throw new Error("Missing transaction id");

  const parsed = read(formData);
  const existing = await prisma.transaction.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new Error("Transaction not found");

  const { toWalletId, categoryId } = await validateRefs(user.id, parsed);

  // Reverse the old effect, apply the new one — netted per wallet.
  const oldDeltas = effects({
    type: existing.type,
    amount: existing.amount,
    walletId: existing.walletId,
    toWalletId: existing.toWalletId,
  });
  const newDeltas = effects({ type: parsed.type, amount: parsed.amount, walletId: parsed.walletId, toWalletId });
  const negatedOld = Object.fromEntries(Object.entries(oldDeltas).map(([k, v]) => [k, -v]));

  await prisma.$transaction([
    prisma.transaction.update({
      where: { id: existing.id },
      data: {
        walletId: parsed.walletId,
        toWalletId,
        categoryId,
        type: parsed.type,
        amount: parsed.amount,
        note: parsed.note,
        date: parsed.date,
      },
    }),
    ...balanceOps(mergeDeltas(negatedOld, newDeltas)),
  ]);

  revalidateAll();
}

export async function deleteTransaction(formData: FormData) {
  const user = await requireUser();
  const id = formData.get("id");
  if (typeof id !== "string" || id.length === 0) throw new Error("Missing transaction id");

  const existing = await prisma.transaction.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new Error("Transaction not found");

  const reverse = Object.fromEntries(
    Object.entries(
      effects({
        type: existing.type,
        amount: existing.amount,
        walletId: existing.walletId,
        toWalletId: existing.toWalletId,
      }),
    ).map(([k, v]) => [k, -v]),
  );

  await prisma.$transaction([
    prisma.transaction.delete({ where: { id: existing.id } }),
    ...balanceOps(reverse),
  ]);

  revalidateAll();
}
