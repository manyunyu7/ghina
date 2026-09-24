"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { deleteSynced } from "@/lib/sync-deletes";
import {
  ALL_PRAYER_IDS,
  PRAYER_NOTE_MAX,
  defaultStatusFor,
  isFardhu,
  isPrayedStatus,
  isValidDateKey,
  prayerEntryError,
  type PrayerFields,
} from "@/lib/prayer-quality";
import { toDTO, type PrayerEntryDTO } from "./types";

export type PrayerInput = {
  date: string;
  prayer: string;
  status?: string;
  qobliyah?: boolean;
  badiyah?: boolean;
  rakaat?: number | null;
  /** ISO timestamp or null. */
  prayedAt?: string | null;
  note?: string | null;
};

type Result = { ok: true; entry: PrayerEntryDTO | null } | { ok: false; error: string };

function revalidate() {
  revalidatePath("/prayers");
  revalidatePath("/prayers/report");
  revalidatePath("/dashboard");
}

/** Create or update the entry for (date, prayer) — status, rawatib, rakaat, time, note. */
export async function savePrayer(input: PrayerInput): Promise<Result> {
  const user = await requireUser();
  const date = String(input?.date ?? "");
  const prayer = String(input?.prayer ?? "");
  if (!isValidDateKey(date)) return { ok: false, error: "Tanggal tidak valid" };
  if (!ALL_PRAYER_IDS.includes(prayer)) return { ok: false, error: "Shalat tidak dikenal" };

  let prayedAt: Date | null = null;
  if (input.prayedAt) {
    prayedAt = new Date(input.prayedAt);
    if (Number.isNaN(prayedAt.getTime())) return { ok: false, error: "Waktu tidak valid" };
  }
  const note = typeof input.note === "string" && input.note.trim() ? input.note.trim().slice(0, PRAYER_NOTE_MAX) : null;
  const status = input.status ?? defaultStatusFor(prayer);
  // Switching to missed/excused clears rawatib (the UI does the same).
  const prayed = isPrayedStatus(status);
  const data: PrayerFields = {
    date,
    prayer,
    status,
    qobliyah: isFardhu(prayer) && prayed ? Boolean(input.qobliyah) : false,
    badiyah: isFardhu(prayer) && prayed ? Boolean(input.badiyah) : false,
    rakaat: input.rakaat ?? null,
    prayedAt,
    note,
  };
  const err = prayerEntryError(data);
  if (err) return { ok: false, error: err };

  const row = await prisma.prayerEntry.upsert({
    where: { userId_date_prayer: { userId: user.id, date, prayer } },
    create: { userId: user.id, ...data },
    update: data,
  });
  revalidate();
  return { ok: true, entry: toDTO(row) };
}

/** Remove the entry for (date, prayer) — back to "Belum diisi" / sunnah not done. */
export async function clearPrayer(input: { date: string; prayer: string }): Promise<Result> {
  const user = await requireUser();
  const date = String(input?.date ?? "");
  const prayer = String(input?.prayer ?? "");
  if (!isValidDateKey(date)) return { ok: false, error: "Tanggal tidak valid" };
  if (!ALL_PRAYER_IDS.includes(prayer)) return { ok: false, error: "Shalat tidak dikenal" };

  const existing = await prisma.prayerEntry.findUnique({
    where: { userId_date_prayer: { userId: user.id, date, prayer } },
    select: { id: true },
  });
  if (existing) await deleteSynced(user.id, "prayers", existing.id);
  revalidate();
  return { ok: true, entry: null };
}
