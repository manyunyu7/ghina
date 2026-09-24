import { NOTE_COLORS, type NoteColorId } from "@/lib/notes";
import type { NoteDTO, NoteLabelDTO } from "@/lib/notes-server";

export type { NoteDTO, NoteLabelDTO };

export type AreaOption = { id: string; name: string; code: string; color: string };
export type WalletOption = { id: string; name: string; currency: string };
export type CategoryOption = { id: string; name: string; type: string };

/** Everything the convert dialogs need besides the note. */
export type ConvertContext = {
  areas: AreaOption[];
  wallets: WalletOption[];
  categories: CategoryOption[];
  currency: string;
};

export type ToastInput = {
  text: string;
  tone?: "success" | "error" | "info";
  action?: { label: string; run: () => void };
  href?: { label: string; url: string };
};
export type PushToast = (t: ToastInput) => void;

/** Card background for a palette id (the web UI is light-only, so the light shade). */
export function noteBg(color: string | null | undefined): string | undefined {
  return NOTE_COLORS.find((c) => c.id === color)?.light;
}

export function colorLabel(color: NoteColorId | null): string {
  return NOTE_COLORS.find((c) => c.id === color)?.label ?? "Default";
}

/** Swatches offered for label colors. */
export const LABEL_COLORS = [
  "#58CC02",
  "#CE82FF",
  "#1CB0F6",
  "#FF4B4B",
  "#FF9600",
  "#FFC800",
  "#2B70C9",
  "#FF86D0",
  "#00CD9C",
  "#777777",
];

/** 75 → "1:15". */
export function formatDuration(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

/** A note with nothing in it (title, body, checklist, media). */
export function isBlankNote(n: { title: string | null; body: string; checklist: { text: string }[]; photos?: string[]; audio?: unknown[] }) {
  return !n.title?.trim() && !n.body.trim() && !n.checklist.some((c) => c.text.trim()) && !n.photos?.length && !n.audio?.length;
}

/** "24 Sep 2026" / "14.05" (today) for the card footer. */
export function formatEdited(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  if (d.toDateString() === now.toDateString())
    return new Intl.DateTimeFormat("id-ID", { hour: "2-digit", minute: "2-digit" }).format(d);
  return new Intl.DateTimeFormat("id-ID", {
    day: "numeric",
    month: "short",
    ...(d.getFullYear() !== now.getFullYear() ? { year: "numeric" } : {}),
  }).format(d);
}

/** Today as YYYY-MM-DD in the browser's zone. */
export function todayKey(): string {
  const d = new Date();
  return new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 10);
}

/** Keyboard shortcuts should not fire while the user types somewhere. */
export function isTypingTarget(t: EventTarget | null): boolean {
  if (!(t instanceof HTMLElement)) return false;
  return t.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(t.tagName);
}

export function newItemId(): string {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `i${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
}
