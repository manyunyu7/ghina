import { writeFile, mkdir, unlink } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { UPLOAD_PATH_RE } from "@/lib/schemas";
import { sniffImageType } from "@/lib/photos";
import { prisma } from "@/lib/prisma";

const UPLOAD_DIR = join(process.cwd(), "public", "uploads");

/**
 * Persist an uploaded image to /public/uploads and return its public path. The type
 * is detected from the file's bytes (JPEG, PNG, WebP, GIF, HEIC/HEIF) — the
 * client-sent MIME type and file name are not trusted — and decides the extension.
 */
export async function saveUpload(file: File, maxBytes: number): Promise<string> {
  if (file.size > maxBytes) throw new Error(`Image is too large (max ${Math.round(maxBytes / 1024 / 1024)} MB)`);
  const bytes = Buffer.from(await file.arrayBuffer());
  const ext = sniffImageType(bytes);
  if (!ext) throw new Error("Please upload an image file (JPEG, PNG, WebP, GIF or HEIC)");
  const name = `${randomUUID()}.${ext}`;
  await mkdir(UPLOAD_DIR, { recursive: true });
  await writeFile(join(UPLOAD_DIR, name), bytes);
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

/**
 * Best-effort removal of uploads that no row references any more (a transaction's
 * `photos` or a food log's `photoUrl`). Call AFTER the DB change is committed. The
 * reference check guards against deleting a file another row still shows (e.g. a
 * duplicated transaction that copied the photo list).
 */
export async function deleteUnreferencedUploads(urls: readonly string[]) {
  for (const url of new Set(urls)) {
    if (!UPLOAD_PATH_RE.test(url)) continue;
    try {
      const [txRefs, foodRefs] = await Promise.all([
        prisma.transaction.count({ where: { photos: { contains: JSON.stringify(url) } } }),
        prisma.foodLog.count({ where: { photoUrl: url } }),
      ]);
      if (txRefs + foodRefs === 0) await deleteUpload(url);
    } catch {
      // best effort
    }
  }
}
