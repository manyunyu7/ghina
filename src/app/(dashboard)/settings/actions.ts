"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/prisma";
import { requireUser } from "@/lib/auth-helpers";
import { profileSchema } from "@/lib/schemas";
import { resetFinanceData } from "@/lib/sync-deletes";

export type SettingsActionResult = { ok: boolean; error?: string };

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
    // Also rotates the sync epoch so mobile clients wipe and re-pull.
    await resetFinanceData(user.id);
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
