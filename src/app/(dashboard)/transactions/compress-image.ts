/**
 * Dependency-free client-side image compression (docs/transaction-photos.md):
 * scale down to ≤ 1600 px wide and re-encode as JPEG (~0.8). Browser-only.
 */

const MAX_WIDTH = 1600;
const QUALITIES = [0.8, 0.65, 0.5];

export class PhotoError extends Error {}

type Decoded = { source: CanvasImageSource; width: number; height: number; close: () => void };

async function decode(file: File): Promise<Decoded> {
  if (typeof createImageBitmap === "function") {
    try {
      const bmp = await createImageBitmap(file, { imageOrientation: "from-image" });
      return { source: bmp, width: bmp.width, height: bmp.height, close: () => bmp.close() };
    } catch {
      // fall through to <img>
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.decoding = "async";
    img.src = url;
    await img.decode();
    return { source: img, width: img.naturalWidth, height: img.naturalHeight, close: () => {} };
  } finally {
    URL.revokeObjectURL(url);
  }
}

function toBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob | null> {
  return new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));
}

function jpegName(name: string): string {
  const base = name.replace(/\.[^.]+$/, "") || "foto";
  return `${base}.jpg`;
}

/**
 * Returns a file ready to upload (≤ maxBytes), or throws a `PhotoError` with a
 * friendly Indonesian message. Keeps the original when re-encoding wouldn't help.
 */
export async function compressImage(file: File, maxBytes: number): Promise<File> {
  const label = `“${file.name || "foto"}”`;
  if (!file.type.startsWith("image/")) throw new PhotoError(`${label} bukan file gambar.`);

  let decoded: Decoded;
  try {
    decoded = await decode(file);
  } catch {
    // The browser can't decode it (e.g. HEIC outside Safari): send as-is if it fits.
    if (file.size <= maxBytes) return file;
    throw new PhotoError(`${label} tidak bisa diproses dan lebih dari ${mb(maxBytes)}.`);
  }

  try {
    const scale = Math.min(1, MAX_WIDTH / decoded.width);
    const width = Math.max(1, Math.round(decoded.width * scale));
    const height = Math.max(1, Math.round(decoded.height * scale));
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("no 2d context");
    ctx.fillStyle = "#fff"; // transparent PNGs → white, not black
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(decoded.source, 0, 0, width, height);

    for (const q of QUALITIES) {
      const blob = await toBlob(canvas, q);
      if (!blob) break;
      // Already small and not resized: re-encoding would only lose quality.
      if (scale === 1 && blob.size >= file.size && file.size <= maxBytes) return file;
      if (blob.size <= maxBytes) {
        return new File([blob], jpegName(file.name), { type: "image/jpeg", lastModified: file.lastModified });
      }
    }
  } catch {
    if (file.size <= maxBytes) return file;
    throw new PhotoError(`Gagal memproses ${label}.`);
  } finally {
    decoded.close();
  }
  throw new PhotoError(`${label} terlalu besar (maks ${mb(maxBytes)}) walau sudah dikompres.`);
}

function mb(bytes: number) {
  return `${Math.round(bytes / 1024 / 1024)} MB`;
}
