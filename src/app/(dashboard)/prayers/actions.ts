"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { PRAYER_IDS } from "./constants";

type Result = { ok: boolean; done?: boolean; error?: string };

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/** Toggle a single prayer for a given day on/off. Returns the resulting state. */
export async function togglePrayer(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const date = String(formData.get("date") ?? "");
  const prayer = String(formData.get("prayer") ?? "");

  if (!DATE_RE.test(date)) return { ok: false, error: "Invalid date" };
  if (!PRAYER_IDS.includes(prayer)) return { ok: false, error: "Invalid prayer" };

  const existing = await prisma.prayerEntry.findUnique({
    where: { userId_date_prayer: { userId: user.id, date, prayer } },
    select: { id: true },
  });

  let done: boolean;
  if (existing) {
    await prisma.prayerEntry.delete({ where: { id: existing.id } });
    done = false;
  } else {
    await prisma.prayerEntry.create({ data: { userId: user.id, date, prayer } });
    done = true;
  }

  revalidatePath("/prayers");
  revalidatePath("/dashboard");
  return { ok: true, done };
}
