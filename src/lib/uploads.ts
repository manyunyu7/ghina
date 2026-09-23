import { writeFile, mkdir, unlink } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { UPLOAD_PATH_RE } from "@/lib/schemas";

const EXT: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
  "image/heic": "heic",
};

const UPLOAD_DIR = join(process.cwd(), "public", "uploads");

/** Persist an uploaded image to /public/uploads and return its public path. */
export async function saveUpload(file: File, maxBytes: number): Promise<string> {
  if (!file.type.startsWith("image/")) throw new Error("Please upload an image file");
  if (file.size > maxBytes) throw new Error(`Image is too large (max ${Math.round(maxBytes / 1024 / 1024)} MB)`);
  const ext = EXT[file.type] ?? "img";
  const name = `${randomUUID()}.${ext}`;
  await mkdir(UPLOAD_DIR, { recursive: true });
  await writeFile(join(UPLOAD_DIR, name), Buffer.from(await file.arrayBuffer()));
  return `/uploads/${name}`;
}

/** Best-effort removal of a previously stored upload. */
export async function deleteUpload(photoUrl: string | null | undefined) {
  if (!photoUrl || !UPLOAD_PATH_RE.test(photoUrl)) return;
  try {
    await unlink(join(process.cwd(), "public", photoUrl));
  } catch {
    // ignore — file may already be gone
  }
}
