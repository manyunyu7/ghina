"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireUser } from "@/lib/auth-helpers";

export type BudgetActionResult = { ok: boolean; error?: string };

const budgetSchema = z.object({
  categoryId: z.string().trim().min(1, "Category is required"),
  amount: z.number().positive("Amount must be greater than 0"),
  month: z.number().int().min(1, "Invalid month").max(12, "Invalid month"),
  year: z.number().int().min(1970, "Invalid year").max(9999, "Invalid year"),
});

function parse(formData: FormData): z.infer<typeof budgetSchema> {
  return budgetSchema.parse({
    categoryId: String(formData.get("categoryId") ?? ""),
    amount: Number(formData.get("amount")),
    month: Number(formData.get("month")),
    year: Number(formData.get("year")),
  });
}

function revalidate() {
  revalidatePath("/budgets");
  revalidatePath("/dashboard");
}

/** Ensures the category exists, belongs to the user, and is an expense category. */
async function assertExpenseCategory(userId: string, categoryId: string): Promise<boolean> {
  const category = await prisma.category.findUnique({
    where: { id: categoryId },
    select: { userId: true, type: true },
  });
  return Boolean(category && category.userId === userId && category.type === "expense");
}

/** Create or update a budget for a category in a given month/year (upsert on the composite unique key). */
export async function setBudget(formData: FormData): Promise<BudgetActionResult> {
  const user = await requireUser();
  try {
    const data = parse(formData);

    if (!(await assertExpenseCategory(user.id, data.categoryId))) {
      return { ok: false, error: "Invalid category" };
    }

    await prisma.budget.upsert({
      where: {
        userId_categoryId_month_year: {
          userId: user.id,
          categoryId: data.categoryId,
          month: data.month,
          year: data.year,
        },
      },
      create: { ...data, userId: user.id },
      update: { amount: data.amount },
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      return { ok: false, error: err.issues[0]?.message ?? "Invalid data" };
    }
    return { ok: false, error: "Failed to save budget" };
  }
  revalidate();
  return { ok: true };
}

/** Update an existing budget's amount by id (with ownership check). */
export async function updateBudget(formData: FormData): Promise<BudgetActionResult> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing budget id" };

  try {
    const existing = await prisma.budget.findUnique({ where: { id }, select: { userId: true } });
    if (!existing || existing.userId !== user.id) {
      return { ok: false, error: "Budget not found" };
    }

    const amount = Number(formData.get("amount"));
    const parsed = z.number().positive("Amount must be greater than 0").safeParse(amount);
    if (!parsed.success) {
      return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid amount" };
    }

    await prisma.budget.update({
      where: { id },
      data: { amount: parsed.data },
    });
  } catch {
    return { ok: false, error: "Failed to update budget" };
  }
  revalidate();
  return { ok: true };
}

/** Delete a budget by id (with ownership check). */
export async function deleteBudget(formData: FormData): Promise<BudgetActionResult> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  if (!id) return { ok: false, error: "Missing budget id" };

  try {
    const existing = await prisma.budget.findUnique({ where: { id }, select: { userId: true } });
    if (!existing || existing.userId !== user.id) {
      return { ok: false, error: "Budget not found" };
    }
    await prisma.budget.delete({ where: { id } });
  } catch {
    return { ok: false, error: "Failed to delete budget" };
  }
  revalidate();
  return { ok: true };
}
