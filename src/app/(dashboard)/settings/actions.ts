"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireUser } from "@/lib/auth-helpers";
import { CURRENCIES } from "@/lib/utils";

export type SettingsActionResult = { ok: boolean; error?: string };

const profileSchema = z.object({
  currency: z.enum(CURRENCIES as [string, ...string[]]),
  name: z.string().trim().min(1, "Name is required").max(60),
});

function revalidate() {
  revalidatePath("/settings");
  revalidatePath("/dashboard");
}

export async function updateProfile(formData: FormData): Promise<SettingsActionResult> {
  const user = await requireUser();
  try {
    const data = profileSchema.parse({
      currency: String(formData.get("currency") ?? user.currency),
      name: String(formData.get("name") ?? user.name ?? ""),
    });
    await prisma.user.update({
      where: { id: user.id },
      data: { currency: data.currency, name: data.name },
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      return { ok: false, error: err.issues[0]?.message ?? "Invalid data" };
    }
    return { ok: false, error: "Failed to update profile" };
  }
  revalidate();
  return { ok: true };
}

export async function resetData(): Promise<SettingsActionResult> {
  const user = await requireUser();
  try {
    await prisma.$transaction([
      prisma.budget.deleteMany({ where: { userId: user.id } }),
      prisma.transaction.deleteMany({ where: { userId: user.id } }),
      prisma.category.deleteMany({ where: { userId: user.id } }),
      prisma.wallet.deleteMany({ where: { userId: user.id } }),
    ]);
  } catch {
    return { ok: false, error: "Failed to reset data" };
  }
  revalidate();
  revalidatePath("/wallets");
  revalidatePath("/categories");
  revalidatePath("/transactions");
  revalidatePath("/budgets");
  return { ok: true };
}
