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

/** Signed effect on wallet balance for income/expense. Transfer is ignored. */
function balanceDelta(type: string, amount: number): number {
  if (type === "income") return amount;
  if (type === "expense") return -amount;
  return 0; // transfer
}

export async function createTransaction(formData: FormData) {
  const user = await requireUser();

  const parsed = baseSchema.parse({
    type: formData.get("type"),
    amount: formData.get("amount"),
    walletId: formData.get("walletId"),
    categoryId: formData.get("categoryId") ?? undefined,
    note: formData.get("note") ?? undefined,
    date: formData.get("date"),
  });

  // Verify the wallet belongs to the user.
  const wallet = await prisma.wallet.findFirst({
    where: { id: parsed.walletId, userId: user.id },
    select: { id: true },
  });
  if (!wallet) throw new Error("Wallet not found");

  // Verify the category (if any) belongs to the user.
  if (parsed.categoryId) {
    const category = await prisma.category.findFirst({
      where: { id: parsed.categoryId, userId: user.id },
      select: { id: true },
    });
    if (!category) throw new Error("Category not found");
  }

  const delta = balanceDelta(parsed.type, parsed.amount);

  await prisma.$transaction([
    prisma.transaction.create({
      data: {
        userId: user.id,
        walletId: parsed.walletId,
        categoryId: parsed.categoryId,
        type: parsed.type,
        amount: parsed.amount,
        note: parsed.note,
        date: parsed.date,
      },
    }),
    prisma.wallet.update({
      where: { id: parsed.walletId },
      data: { balance: { increment: delta } },
    }),
  ]);

  revalidateAll();
}

export async function updateTransaction(formData: FormData) {
  const user = await requireUser();

  const id = formData.get("id");
  if (typeof id !== "string" || id.length === 0) throw new Error("Missing transaction id");

  const parsed = baseSchema.parse({
    type: formData.get("type"),
    amount: formData.get("amount"),
    walletId: formData.get("walletId"),
    categoryId: formData.get("categoryId") ?? undefined,
    note: formData.get("note") ?? undefined,
    date: formData.get("date"),
  });

  // Load existing transaction and confirm ownership.
  const existing = await prisma.transaction.findFirst({
    where: { id, userId: user.id },
  });
  if (!existing) throw new Error("Transaction not found");

  // Verify the (possibly new) wallet belongs to the user.
  const wallet = await prisma.wallet.findFirst({
    where: { id: parsed.walletId, userId: user.id },
    select: { id: true },
  });
  if (!wallet) throw new Error("Wallet not found");

  if (parsed.categoryId) {
    const category = await prisma.category.findFirst({
      where: { id: parsed.categoryId, userId: user.id },
      select: { id: true },
    });
    if (!category) throw new Error("Category not found");
  }

  const oldDelta = balanceDelta(existing.type, existing.amount);
  const newDelta = balanceDelta(parsed.type, parsed.amount);

  const ops: Prisma.PrismaPromise<unknown>[] = [
    prisma.transaction.update({
      where: { id: existing.id },
      data: {
        walletId: parsed.walletId,
        categoryId: parsed.categoryId,
        type: parsed.type,
        amount: parsed.amount,
        note: parsed.note,
        date: parsed.date,
      },
    }),
  ];

  if (existing.walletId === parsed.walletId) {
    // Same wallet: net the difference.
    ops.push(
      prisma.wallet.update({
        where: { id: parsed.walletId },
        data: { balance: { increment: newDelta - oldDelta } },
      }),
    );
  } else {
    // Wallet changed: reverse on old wallet, apply on new wallet.
    ops.push(
      prisma.wallet.update({
        where: { id: existing.walletId },
        data: { balance: { increment: -oldDelta } },
      }),
      prisma.wallet.update({
        where: { id: parsed.walletId },
        data: { balance: { increment: newDelta } },
      }),
    );
  }

  await prisma.$transaction(ops);

  revalidateAll();
}

export async function deleteTransaction(formData: FormData) {
  const user = await requireUser();

  const id = formData.get("id");
  if (typeof id !== "string" || id.length === 0) throw new Error("Missing transaction id");

  const existing = await prisma.transaction.findFirst({
    where: { id, userId: user.id },
  });
  if (!existing) throw new Error("Transaction not found");

  // Reverse the original effect on the wallet balance.
  const delta = balanceDelta(existing.type, existing.amount);

  await prisma.$transaction([
    prisma.transaction.delete({ where: { id: existing.id } }),
    prisma.wallet.update({
      where: { id: existing.walletId },
      data: { balance: { increment: -delta } },
    }),
  ]);

  revalidateAll();
}
