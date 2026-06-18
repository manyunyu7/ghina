"use server";

import { writeFile, mkdir, unlink } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";

type Result = { ok: boolean; error?: string };

const MEALS = ["breakfast", "lunch", "dinner", "snack"];
const MAX_BYTES = 8 * 1024 * 1024;
const EXT: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
  "image/heic": "heic",
};

const UPLOAD_DIR = join(process.cwd(), "public", "uploads");

/** Persist an uploaded image to /public/uploads and return its public path. */
async function saveUpload(file: File): Promise<string> {
  if (!file.type.startsWith("image/")) throw new Error("Please upload an image file");
  if (file.size > MAX_BYTES) throw new Error("Image is too large (max 8 MB)");
  const ext = EXT[file.type] ?? "img";
  const name = `${randomUUID()}.${ext}`;
  await mkdir(UPLOAD_DIR, { recursive: true });
  await writeFile(join(UPLOAD_DIR, name), Buffer.from(await file.arrayBuffer()));
  return `/uploads/${name}`;
}

/** Best-effort removal of a previously stored upload. */
async function deleteUpload(photoUrl: string | null | undefined) {
  if (!photoUrl?.startsWith("/uploads/")) return;
  try {
    await unlink(join(process.cwd(), "public", photoUrl));
  } catch {
    // ignore — file may already be gone
  }
}

type Parsed = { date: Date; name: string; meal: string | null; calories: number | null; note: string | null };

function parse(formData: FormData): { data?: Parsed; error?: string } {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return { error: "Name is required" };
  if (name.length > 120) return { error: "Name is too long" };

  const dateStr = String(formData.get("date") ?? "").trim();
  const date = dateStr ? new Date(dateStr) : new Date();
  if (Number.isNaN(date.getTime())) return { error: "Invalid date" };

  const mealRaw = String(formData.get("meal") ?? "").trim();
  const meal = mealRaw && MEALS.includes(mealRaw) ? mealRaw : null;

  const calStr = String(formData.get("calories") ?? "").trim();
  let calories: number | null = null;
  if (calStr) {
    const n = Number(calStr);
    if (!Number.isFinite(n) || n < 0 || n > 20000) return { error: "Calories looks off (0–20000)" };
    calories = Math.round(n);
  }

  const noteRaw = String(formData.get("note") ?? "").trim();
  return { data: { date, name, meal, calories, note: noteRaw || null } };
}

export async function createFood(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const { data, error } = parse(formData);
  if (!data) return { ok: false, error };

  let photoUrl: string | null = null;
  const file = formData.get("photo");
  try {
    if (file instanceof File && file.size > 0) photoUrl = await saveUpload(file);
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Upload failed" };
  }

  await prisma.foodLog.create({ data: { userId: user.id, ...data, photoUrl } });
  revalidatePath("/food");
  revalidatePath("/dashboard");
  return { ok: true };
}

export async function updateFood(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  const existing = await prisma.foodLog.findFirst({ where: { id, userId: user.id } });
  if (!existing) return { ok: false, error: "Entry not found" };

  const { data, error } = parse(formData);
  if (!data) return { ok: false, error };

  let photoUrl = existing.photoUrl;
  const file = formData.get("photo");
  const removePhoto = formData.get("removePhoto") === "true";
  try {
    if (file instanceof File && file.size > 0) {
      photoUrl = await saveUpload(file);
      await deleteUpload(existing.photoUrl);
    } else if (removePhoto) {
      await deleteUpload(existing.photoUrl);
      photoUrl = null;
    }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Upload failed" };
  }

  await prisma.foodLog.update({ where: { id }, data: { ...data, photoUrl } });
  revalidatePath("/food");
  revalidatePath("/dashboard");
  return { ok: true };
}

export async function deleteFood(formData: FormData): Promise<Result> {
  const user = await requireUser();
  const id = String(formData.get("id") ?? "");
  const existing = await prisma.foodLog.findFirst({ where: { id, userId: user.id } });
  if (!existing) return { ok: false, error: "Entry not found" };

  await deleteUpload(existing.photoUrl);
  await prisma.foodLog.delete({ where: { id } });
  revalidatePath("/food");
  revalidatePath("/dashboard");
  return { ok: true };
}
