"use server";

import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireUser } from "@/lib/auth-helpers";
import { transactionSchema } from "@/lib/schemas";
import {
  createLedgerTransaction,
  deleteLedgerTransaction,
  updateLedgerTransaction,
  validateTransactionRefs,
} from "@/lib/ledger";

function revalidateAll() {
  revalidatePath("/transactions");
  revalidatePath("/dashboard");
  revalidatePath("/wallets");
}

function read(formData: FormData) {
  return transactionSchema.parse({
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
  const { toWalletId, categoryId } = await validateTransactionRefs(prisma, user.id, parsed);

  await prisma.$transaction((db) =>
    createLedgerTransaction(db, user.id, { ...parsed, toWalletId, categoryId }),
  );

  revalidateAll();
}

export async function updateTransaction(formData: FormData) {
  const user = await requireUser();
  const id = formData.get("id");
  if (typeof id !== "string" || id.length === 0) throw new Error("Missing transaction id");

  const parsed = read(formData);
  const existing = await prisma.transaction.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new Error("Transaction not found");

  const { toWalletId, categoryId } = await validateTransactionRefs(prisma, user.id, parsed);

  // Reverses the old effect and applies the new one — netted per wallet.
  await prisma.$transaction((db) => updateLedgerTransaction(db, existing, { ...parsed, toWalletId, categoryId }));

  revalidateAll();
}

export async function deleteTransaction(formData: FormData) {
  const user = await requireUser();
  const id = formData.get("id");
  if (typeof id !== "string" || id.length === 0) throw new Error("Missing transaction id");

  const existing = await prisma.transaction.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new Error("Transaction not found");

  await prisma.$transaction((db) => deleteLedgerTransaction(db, existing));

  revalidateAll();
}
