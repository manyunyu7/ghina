"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";

type Result = { ok: boolean; error?: string };

type Parsed = {
  date: Date;
  weight: number | null;
  systolic: number | null;
  diastolic: number | null;
  pulse: number | null;
  note: string | null;
};

function num(v: FormDataEntryValue | null): number | null | undefined {
  const s = String(v ?? "").trim();
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : undefined; // undefined = invalid
}

function parse(formData: FormData): { data?: Parsed; error?: string } {
  const dateStr = String(formData.get("date") ?? "").trim();
  const date = dateStr ? new Date(dateStr) : new Date();
  if (Number.isNaN(date.getTime())) return { error: "Invalid date" };

  const weight = num(formData.get("weight"));
  const systolic = num(formData.get("systolic"));
  const diastolic = num(formData.get("diastolic"));
  const pulse = num(formData.get("pulse"));
  if (weight === undefined || systolic === undefined || diastolic === undefined || pulse === undefined)
    return { error: "Please enter valid numbers" };

  if (weight != null && (weight < 1 || weight > 500)) return { error: "Weight looks off (1–500 kg)" };
  if (systolic != null && (systolic < 50 || systolic > 300)) return { error: "Systolic looks off (50–300)" };
  if (diastolic != null && (diastolic < 30 || diastolic > 200)) return { error: "Diastolic looks off (30–200)" };
  if (pulse != null && (pulse < 20 || pulse > 250)) return { error: "Pulse looks off (20–250)" };

  // Blood pressure needs both numbers.
  if ((systolic != null) !== (diastolic != null))
    return { error: "Enter both systolic and diastolic for blood pressure" };

  if (weight == null && systolic == null && pulse == null)
    return { error: "Enter at least one measurement" };

  const noteRaw = String(formData.get("note") ?? "").trim();
  return { data: { date, weight, systolic, diastolic, pulse, note: noteRaw || null } };
}

export async function createHealthEntry(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const { data, error } = parse(formData);
  if (!data) return { ok: false, error };

  await prisma.healthEntry.create({ data: { userId: user.id, ...data } });
  revalidatePath("/health");
  revalidatePath("/dashboard");
  return { ok: true };
}

export async function updateHealthEntry(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  const existing = await prisma.healthEntry.findFirst({ where: { id, userId: user.id }, select: { id: true } });
  if (!existing) return { ok: false, error: "Entry not found" };

  const { data, error } = parse(formData);
  if (!data) return { ok: false, error };

  await prisma.healthEntry.update({ where: { id }, data });
  revalidatePath("/health");
  revalidatePath("/dashboard");
  return { ok: true };
}

export async function deleteHealthEntry(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  const existing = await prisma.healthEntry.findFirst({ where: { id, userId: user.id }, select: { id: true } });
  if (!existing) return { ok: false, error: "Entry not found" };

  await prisma.healthEntry.delete({ where: { id } });
  revalidatePath("/health");
  revalidatePath("/dashboard");
  return { ok: true };
}
