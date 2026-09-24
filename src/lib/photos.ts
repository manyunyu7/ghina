import { z } from "zod";
import { UPLOAD_PATH_RE } from "@/lib/schemas";

/**
 * Transaction photos — pure helpers (docs/transaction-photos.md). Stored as a JSON
 * array string in `Transaction.photos`; on the sync wire an array of strings.
 */

export const MAX_TRANSACTION_PHOTOS = 5;
/** Per-file limit for photo uploads (web action and mobile upload endpoint). */
export const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

/**
 * ≤ 5 relative upload paths, each returned by our upload code (`/uploads/<name>.<ext>`).
 * Duplicates are dropped (first wins), order is kept.
 */
export const photosSchema = z
  .array(z.string().regex(UPLOAD_PATH_RE, "Invalid photo URL"), { message: "photos must be an array of URLs" })
  .transform((xs) => [...new Set(xs)])
  .refine((xs) => xs.length <= MAX_TRANSACTION_PHOTOS, `At most ${MAX_TRANSACTION_PHOTOS} photos`);

/** Stored column → list. Lenient: bad JSON or invalid entries are dropped, never thrown. */
export function parsePhotos(stored: string | null | undefined): string[] {
  if (!stored) return [];
  try {
    const v: unknown = JSON.parse(stored);
    if (!Array.isArray(v)) return [];
    return [...new Set(v.filter((x): x is string => typeof x === "string" && UPLOAD_PATH_RE.test(x)))];
  } catch {
    return [];
  }
}

/** List → stored column. */
export function serializePhotos(list: readonly string[]): string {
  return JSON.stringify([...list]);
}

/** Photos in `before` that are no longer in `after` — their files should be deleted. */
export function removedPhotos(before: readonly string[], after: readonly string[]): string[] {
  const keep = new Set(after);
  return before.filter((u) => !keep.has(u));
}

/** File extensions of the image types uploads accept. */
export type ImageExt = "jpg" | "png" | "webp" | "gif" | "heic" | "heif";

const HEIC_BRANDS = new Set(["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs"]);
const HEIF_BRANDS = new Set(["mif1", "msf1", "heif"]);

/**
 * The image type of a file judged by its first bytes (magic number), never by the
 * client-sent MIME type or name: JPEG, PNG, WebP, GIF, HEIC/HEIF. Anything else —
 * SVG, HTML, text, AVIF, … — is null.
 */
export function sniffImageType(bytes: Uint8Array): ImageExt | null {
  const at = (i: number, sig: readonly number[]) => sig.every((b, k) => bytes[i + k] === b);
  const ascii = (i: number, n: number) =>
    bytes.length >= i + n ? String.fromCharCode(...bytes.subarray(i, i + n)) : "";
  if (at(0, [0xff, 0xd8, 0xff])) return "jpg";
  if (at(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "png";
  if (ascii(0, 6) === "GIF87a" || ascii(0, 6) === "GIF89a") return "gif";
  if (ascii(0, 4) === "RIFF" && ascii(8, 4) === "WEBP") return "webp";
  if (ascii(4, 4) === "ftyp") {
    const brand = ascii(8, 4);
    if (HEIC_BRANDS.has(brand)) return "heic";
    if (HEIF_BRANDS.has(brand)) return "heif";
  }
  return null;
}
