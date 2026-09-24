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
import { MAX_PHOTO_BYTES, MAX_TRANSACTION_PHOTOS, parsePhotos, removedPhotos, serializePhotos } from "@/lib/photos";
import { deleteUnreferencedUploads, deleteUpload, saveUpload } from "@/lib/uploads";

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

/**
 * Photo fields (docs/transaction-photos.md), all optional:
 * - `photos`: File(s) to add (multiple entries allowed; empty files ignored), ≤ 5 MB each.
 * - `keepPhotos`: existing URLs to keep, in display order — only read on update when
 *   `photosManaged=1` is present. Without `photosManaged` an update keeps every stored
 *   photo, so forms without the photo UI behave as before.
 * Kept photos come first, then new files; at most 5 in total.
 */
function newPhotoFiles(formData: FormData): File[] {
  return formData.getAll("photos").filter((f): f is File => f instanceof File && f.size > 0);
}

function keptPhotos(formData: FormData, stored: string[]): string[] {
  if (formData.get("photosManaged") !== "1") return stored;
  const keep = formData.getAll("keepPhotos").filter((v): v is string => typeof v === "string");
  // Only URLs this transaction already has — never adopt an arbitrary path.
  return [...new Set(keep)].filter((u) => stored.includes(u));
}

/** Save the new files; if any fails, remove the ones already written and rethrow. */
async function saveNewPhotos(files: File[], alreadyKept: number): Promise<string[]> {
  if (alreadyKept + files.length > MAX_TRANSACTION_PHOTOS) {
    throw new Error(`At most ${MAX_TRANSACTION_PHOTOS} photos per transaction`);
  }
  const saved: string[] = [];
  try {
    for (const f of files) saved.push(await saveUpload(f, MAX_PHOTO_BYTES));
  } catch (e) {
    await Promise.all(saved.map((u) => deleteUpload(u)));
    throw e;
  }
  return saved;
}

export async function createTransaction(formData: FormData) {
  const user = await requireUser();
  const parsed = read(formData);
  const { toWalletId, categoryId } = await validateTransactionRefs(prisma, user.id, parsed);

  const added = await saveNewPhotos(newPhotoFiles(formData), 0);
  try {
    await prisma.$transaction((db) =>
      createLedgerTransaction(db, user.id, { ...parsed, toWalletId, categoryId, photos: serializePhotos(added) }),
    );
  } catch (e) {
    await Promise.all(added.map((u) => deleteUpload(u)));
    throw e;
  }

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

  const stored = parsePhotos(existing.photos);
  const kept = keptPhotos(formData, stored);
  const added = await saveNewPhotos(newPhotoFiles(formData), kept.length);
  const photos = [...kept, ...added];

  try {
    // Reverses the old effect and applies the new one — netted per wallet.
    await prisma.$transaction((db) =>
      updateLedgerTransaction(db, existing, { ...parsed, toWalletId, categoryId, photos: serializePhotos(photos) }),
    );
  } catch (e) {
    await Promise.all(added.map((u) => deleteUpload(u)));
    throw e;
  }
  await deleteUnreferencedUploads(removedPhotos(stored, photos));

  revalidateAll();
}

export async function deleteTransaction(formData: FormData) {
  const user = await requireUser();
  const id = formData.get("id");
  if (typeof id !== "string" || id.length === 0) throw new Error("Missing transaction id");

  const existing = await prisma.transaction.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new Error("Transaction not found");

  const files = await prisma.$transaction((db) => deleteLedgerTransaction(db, existing));
  await deleteUnreferencedUploads(files);

  revalidateAll();
}
