import { writeFile, mkdir, unlink } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { sniffImageType } from "@/lib/photos";
import { MAX_BYTES_BY_KIND, sniffMediaType, type MediaKind } from "@/lib/media";
import { prisma } from "@/lib/prisma";

const NOT_AN_IMAGE = "File bukan gambar yang didukung (JPEG, PNG, WebP, GIF atau HEIC)";

const UPLOAD_DIR = join(process.cwd(), "public", "uploads");

/**
 * A path our upload code wrote (`/uploads/<name>.<ext>`, ext may contain digits: m4a,
 * and legacy `.img`) — also guards unlink against path traversal.
 */
const isUploadPath = (u: string) => /^\/uploads\/[A-Za-z0-9-]+\.[a-z0-9]+$/.test(u);

/**
 * Persist an uploaded image to /public/uploads and return its public path. The type
 * is detected from the file's bytes (JPEG, PNG, WebP, GIF, HEIC/HEIF) — the
 * client-sent MIME type and file name are not trusted — and decides the extension.
 */
export async function saveUpload(file: File, maxBytes: number): Promise<string> {
  if (file.size > maxBytes) throw new Error(`Foto terlalu besar (maks ${Math.round(maxBytes / 1024 / 1024)} MB)`);
  const bytes = Buffer.from(await file.arrayBuffer());
  const ext = sniffImageType(bytes);
  if (!ext) throw new Error(NOT_AN_IMAGE);
  const name = `${randomUUID()}.${ext}`;
  await mkdir(UPLOAD_DIR, { recursive: true });
  await writeFile(join(UPLOAD_DIR, name), bytes);
  return `/uploads/${name}`;
}

const mb = (n: number) => Math.round(n / 1024 / 1024);

/**
 * Persist an uploaded image or audio file (docs/notes.md "Voice notes"). The kind and
 * extension come from the file's bytes (`sniffMediaType`); `kinds` limits what is
 * accepted. Size limits per kind: images ≤ 5 MB, audio ≤ 20 MB (`MAX_BYTES_BY_KIND`).
 */
export async function saveMediaUpload(
  file: File,
  kinds: readonly MediaKind[] = ["image", "audio"],
): Promise<{ url: string; kind: MediaKind }> {
  const maxAny = Math.max(...kinds.map((k) => MAX_BYTES_BY_KIND[k]));
  if (file.size > maxAny) throw new Error(`File terlalu besar (maks ${mb(maxAny)} MB)`);
  const bytes = Buffer.from(await file.arrayBuffer());
  const type = sniffMediaType(bytes);
  if (!type || !kinds.includes(type.kind)) {
    throw new Error(
      kinds.length === 1 && kinds[0] === "audio"
        ? "Unggah file audio (M4A/AAC, MP3, Ogg/Opus atau WebM)"
        : kinds.length === 1
          ? NOT_AN_IMAGE
          : "Unggah gambar (JPEG, PNG, WebP, GIF, HEIC) atau audio (M4A/AAC, MP3, Ogg/Opus, WebM)",
    );
  }
  const max = MAX_BYTES_BY_KIND[type.kind];
  if (bytes.length > max) {
    throw new Error(type.kind === "image" ? `Foto terlalu besar (maks ${mb(max)} MB)` : `Audio terlalu besar (maks ${mb(max)} MB)`);
  }
  const name = `${randomUUID()}.${type.ext}`;
  await mkdir(UPLOAD_DIR, { recursive: true });
  await writeFile(join(UPLOAD_DIR, name), bytes);
  return { url: `/uploads/${name}`, kind: type.kind };
}

/** Best-effort removal of a previously stored upload. */
export async function deleteUpload(photoUrl: string | null | undefined) {
  if (!photoUrl || !isUploadPath(photoUrl)) return;
  try {
    await unlink(join(process.cwd(), "public", photoUrl));
  } catch {
    // ignore — file may already be gone
  }
}

/**
 * Best-effort removal of uploads that no row references any more (a transaction's
 * `photos`, a food log's `photoUrl`, a note's `photos`/`audio`, a content item's
 * `photos`). Call AFTER the DB change is committed. The
 * reference check guards against deleting a file another row still shows (e.g. a
 * duplicated transaction that copied the photo list).
 */
export async function deleteUnreferencedUploads(urls: readonly string[]) {
  for (const url of new Set(urls)) {
    if (!isUploadPath(url)) continue;
    try {
      // JSON columns hold the URL as a JSON string ("…"), so a quoted `contains` is exact.
      const quoted = JSON.stringify(url);
      const refs = await Promise.all([
        prisma.transaction.count({ where: { photos: { contains: quoted } } }),
        prisma.foodLog.count({ where: { photoUrl: url } }),
        prisma.note.count({ where: { OR: [{ photos: { contains: quoted } }, { audio: { contains: quoted } }] } }),
        prisma.contentItem.count({ where: { photos: { contains: quoted } } }),
      ]);
      if (refs.every((n) => n === 0)) await deleteUpload(url);
    } catch {
      // best effort
    }
  }
}
