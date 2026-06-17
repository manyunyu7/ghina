"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireUser } from "@/lib/auth-helpers";
import {
  CATEGORY_ICONS,
  COLOR_PALETTE,
  DEFAULT_EXPENSE_CATEGORIES,
  DEFAULT_INCOME_CATEGORIES,
} from "@/lib/constants";

const categorySchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(60),
  type: z.enum(["expense", "income"]),
  color: z.string().regex(/^#[0-9a-fA-F]{6}$/, "Invalid color"),
  icon: z.enum(CATEGORY_ICONS as [string, ...string[]]),
});

export type CategoryActionResult = { ok: boolean; error?: string };

function parse(formData: FormData): z.infer<typeof categorySchema> {
  const colorRaw = String(formData.get("color") ?? "");
  const color = COLOR_PALETTE.includes(colorRaw) ? colorRaw : COLOR_PALETTE[0];
  const iconRaw = String(formData.get("icon") ?? "").trim();
  const icon = CATEGORY_ICONS.includes(iconRaw) ? iconRaw : CATEGORY_ICONS[CATEGORY_ICONS.length - 1];

  return categorySchema.parse({
    name: String(formData.get("name") ?? ""),
    type: String(formData.get("type") ?? "expense"),
    color,
    icon,
  });
}

function revalidate() {
  revalidatePath("/categories");
  revalidatePath("/dashboard");
}

export async function createCategory(formData: FormData): Promise<CategoryActionResult> {
  const user = await requireUser();
  try {
    const data = parse(formData);
    await prisma.category.create({
      data: { ...data, userId: user.id },
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      return { ok: false, error: err.issues[0]?.message ?? "Invalid data" };
    }
    return { ok: false, error: "Failed to create category" };
  }
  revalidate();
  return { ok: true };
}

export async function updateCategory(formData: FormData): Promise<CategoryActionResult> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing category id" };

  try {
    // Verify ownership before mutating.
    const existing = await prisma.category.findUnique({ where: { id }, select: { userId: true } });
    if (!existing || existing.userId !== user.id) {
      return { ok: false, error: "Category not found" };
    }

    const data = parse(formData);
    await prisma.category.update({
      where: { id },
      data,
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      return { ok: false, error: err.issues[0]?.message ?? "Invalid data" };
    }
    return { ok: false, error: "Failed to update category" };
  }
  revalidate();
  return { ok: true };
}

export async function deleteCategory(formData: FormData): Promise<CategoryActionResult> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing category id" };

  try {
    // Verify ownership before deleting; transactions.categoryId is set null per schema.
    const existing = await prisma.category.findUnique({ where: { id }, select: { userId: true } });
    if (!existing || existing.userId !== user.id) {
      return { ok: false, error: "Category not found" };
    }
    await prisma.category.delete({ where: { id } });
  } catch {
    return { ok: false, error: "Failed to delete category" };
  }
  revalidate();
  return { ok: true };
}

export async function seedDefaultCategories(): Promise<CategoryActionResult> {
  const user = await requireUser();
  try {
    // Skip names that already exist for this user (idempotent-ish).
    const existing = await prisma.category.findMany({
      where: { userId: user.id },
      select: { name: true },
    });
    const taken = new Set(existing.map((c) => c.name.toLowerCase()));

    const toCreate = [
      ...DEFAULT_EXPENSE_CATEGORIES.map((c) => ({ ...c, type: "expense" })),
      ...DEFAULT_INCOME_CATEGORIES.map((c) => ({ ...c, type: "income" })),
    ].filter((c) => !taken.has(c.name.toLowerCase()));

    if (toCreate.length > 0) {
      await prisma.category.createMany({
        data: toCreate.map((c) => ({ ...c, userId: user.id })),
      });
    }
  } catch {
    return { ok: false, error: "Failed to add default categories" };
  }
  revalidate();
  return { ok: true };
}
