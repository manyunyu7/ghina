"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";

const schema = z.object({
  name: z.string().trim().min(1, "Name is required").max(80),
  amount: z.coerce.number().positive("Amount must be greater than 0"),
  currency: z.string().min(1).max(8),
  cycle: z.enum(["weekly", "monthly", "yearly"]),
  nextBilling: z.coerce.date(),
  categoryId: z.string().optional().nullable(),
  walletId: z.string().optional().nullable(),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/, "Invalid color").default("#6366f1"),
  icon: z.string().min(1).default("credit-card"),
  note: z.string().max(200).optional().nullable(),
  active: z.coerce.boolean().optional(),
});

type Result = { ok: boolean; error?: string };

function parse(formData: FormData) {
  const emptyToNull = (v: FormDataEntryValue | null) => (v === null || v === "" ? null : String(v));
  return schema.safeParse({
    name: formData.get("name"),
    amount: formData.get("amount"),
    currency: formData.get("currency") || "IDR",
    cycle: formData.get("cycle") || "monthly",
    nextBilling: formData.get("nextBilling"),
    categoryId: emptyToNull(formData.get("categoryId")),
    walletId: emptyToNull(formData.get("walletId")),
    color: formData.get("color") || "#6366f1",
    icon: formData.get("icon") || "credit-card",
    note: emptyToNull(formData.get("note")),
    active: formData.get("active") !== "false",
  });
}

/** Confirm that any referenced category/wallet belongs to the user (defends against forged ids). */
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
  revalidatePath("/subscriptions");
  revalidatePath("/dashboard");
}

export async function createSubscription(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const parsed = parse(formData);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  const d = parsed.data;

  try {
    await assertOwnership(user.id, d.categoryId, d.walletId);
    await prisma.subscription.create({
      data: {
        userId: user.id,
        name: d.name,
        amount: d.amount,
        currency: d.currency,
        cycle: d.cycle,
        nextBilling: d.nextBilling,
        categoryId: d.categoryId ?? null,
        walletId: d.walletId ?? null,
        color: d.color,
        icon: d.icon,
        note: d.note ?? null,
        active: d.active ?? true,
      },
    });
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Failed to create" };
  }
  revalidate();
  return { ok: true };
}

export async function updateSubscription(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing id" };

  const parsed = parse(formData);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  const d = parsed.data;

  const existing = await prisma.subscription.findFirst({ where: { id, userId: user.id }, select: { id: true } });
  if (!existing) return { ok: false, error: "Subscription not found" };

  try {
    await assertOwnership(user.id, d.categoryId, d.walletId);
    await prisma.subscription.update({
      where: { id },
      data: {
        name: d.name,
        amount: d.amount,
        currency: d.currency,
        cycle: d.cycle,
        nextBilling: d.nextBilling,
        categoryId: d.categoryId ?? null,
        walletId: d.walletId ?? null,
        color: d.color,
        icon: d.icon,
        note: d.note ?? null,
        active: d.active ?? true,
      },
    });
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Failed to update" };
  }
  revalidate();
  return { ok: true };
}

export async function deleteSubscription(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  const existing = await prisma.subscription.findFirst({ where: { id, userId: user.id }, select: { id: true } });
  if (!existing) return { ok: false, error: "Subscription not found" };

  await prisma.subscription.delete({ where: { id } });
  revalidate();
  return { ok: true };
}

export async function toggleSubscription(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  const existing = await prisma.subscription.findFirst({ where: { id, userId: user.id }, select: { active: true } });
  if (!existing) return { ok: false, error: "Subscription not found" };

  await prisma.subscription.update({ where: { id }, data: { active: !existing.active } });
  revalidate();
  return { ok: true };
}
