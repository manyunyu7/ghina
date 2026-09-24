import { sniffImageType, MAX_PHOTO_BYTES, type ImageExt } from "@/lib/photos";

/**
 * Upload kinds (docs/notes.md "Voice notes"): images (photos) and audio (voice notes).
 * Pure helpers — the type of a file is always judged by its first bytes, never by the
 * client-sent MIME type or file name.
 */

export type AudioExt = "m4a" | "aac" | "mp3" | "ogg" | "webm";
export type MediaKind = "image" | "audio";

/** Per-file limit for audio uploads (voice notes: ≤ 10 min AAC ~64 kbps ≈ 5 MB). */
export const MAX_AUDIO_BYTES = 20 * 1024 * 1024;
export const MAX_BYTES_BY_KIND: Record<MediaKind, number> = { image: MAX_PHOTO_BYTES, audio: MAX_AUDIO_BYTES };

export const IMAGE_EXTS = ["jpg", "png", "webp", "gif", "heic", "heif"] as const satisfies readonly ImageExt[];
export const AUDIO_EXTS = ["m4a", "aac", "mp3", "ogg", "webm"] as const satisfies readonly AudioExt[];

/** An uploaded image path (`/uploads/<name>.<image ext>`). */
export const IMAGE_UPLOAD_RE = new RegExp(`^/uploads/[A-Za-z0-9-]+\\.(${IMAGE_EXTS.join("|")})$`);
/** An uploaded audio path (`/uploads/<name>.<audio ext>`). */
export const AUDIO_UPLOAD_RE = new RegExp(`^/uploads/[A-Za-z0-9-]+\\.(${AUDIO_EXTS.join("|")})$`);

/** MIME type served / used for playback per audio extension. */
export const AUDIO_MIME: Record<AudioExt, string> = {
  m4a: "audio/mp4",
  aac: "audio/aac",
  mp3: "audio/mpeg",
  ogg: "audio/ogg",
  webm: "audio/webm",
};

// ISO-BMFF major brands of MP4/M4A/3GP files (AAC voice recordings from Android/iOS).
// HEIC/HEIF brands are matched as images first (sniffImageType).
const MP4_BRANDS = new Set(["M4A ", "M4B ", "mp41", "mp42", "isom", "iso2", "iso4", "iso5", "iso6", "dash", "3gp4", "3gp5", "3gp6", "3g2a", "MSNV", "f4a "]);

/**
 * The audio type of a file by its magic bytes: MP4/M4A (ISO-BMFF `ftyp`), raw AAC (ADTS),
 * MP3 (ID3 tag or MPEG frame sync), Ogg (Vorbis/Opus), WebM/Matroska (EBML). Else null.
 * (MP4/WebM containers could hold video; they are still stored/served as audio.)
 */
export function sniffAudioType(bytes: Uint8Array): AudioExt | null {
  const ascii = (i: number, n: number) =>
    bytes.length >= i + n ? String.fromCharCode(...bytes.subarray(i, i + n)) : "";
  if (bytes.length < 4) return null;
  if (ascii(4, 4) === "ftyp" && MP4_BRANDS.has(ascii(8, 4))) return "m4a";
  if (ascii(0, 4) === "OggS") return "ogg";
  if (bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3) return "webm";
  if (ascii(0, 3) === "ID3") return "mp3";
  if (bytes[0] === 0xff) {
    const b1 = bytes[1];
    // ADTS: 12-bit sync, layer bits 00.
    if ((b1 & 0xf6) === 0xf0) return "aac";
    // MPEG audio frame: 11-bit sync, version != reserved (01), layer != reserved (00).
    if ((b1 & 0xe0) === 0xe0 && ((b1 >> 3) & 0x03) !== 0x01 && ((b1 >> 1) & 0x03) !== 0x00) {
      const b2 = bytes[2] ?? 0;
      // bitrate index 1111 and sample-rate index 11 are invalid.
      if ((b2 & 0xf0) !== 0xf0 && (b2 & 0x0c) !== 0x0c) return "mp3";
    }
  }
  return null;
}

/** Image or audio type of a file (images first, so HEIC never reads as MP4 audio). */
export function sniffMediaType(bytes: Uint8Array): { kind: MediaKind; ext: ImageExt | AudioExt } | null {
  const img = sniffImageType(bytes);
  if (img) return { kind: "image", ext: img };
  const audio = sniffAudioType(bytes);
  if (audio) return { kind: "audio", ext: audio };
  return null;
}
