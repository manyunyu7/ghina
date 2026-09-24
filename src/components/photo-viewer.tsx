"use client";

import * as React from "react";
import { createPortal } from "react-dom";
import { ChevronLeft, ChevronRight, Download, ExternalLink, Paperclip, X } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Full-screen, accessible photo lightbox (docs/transaction-photos.md).
 * Esc closes, ←/→ move between photos, Tab is trapped inside, focus returns to the
 * opener on close. Render it only while open (`{open && <PhotoViewer … />}`) so the
 * index initializes from `startIndex` on every open.
 */
export function PhotoViewer({
  photos,
  startIndex = 0,
  onClose,
  title = "Foto transaksi",
}: {
  photos: readonly string[];
  startIndex?: number;
  onClose: () => void;
  title?: string;
}) {
  const count = photos.length;
  const [index, setIndex] = React.useState(() => Math.min(Math.max(0, startIndex), Math.max(0, count - 1)));
  const dialogRef = React.useRef<HTMLDivElement>(null);
  const closeRef = React.useRef<HTMLButtonElement>(null);
  const onCloseRef = React.useRef(onClose);
  React.useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  const go = React.useCallback(
    (delta: number) => setIndex((i) => (count === 0 ? 0 : (i + delta + count) % count)),
    [count],
  );

  // Focus management + scroll lock. Restore focus and overflow on close.
  React.useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeRef.current?.focus();
    return () => {
      document.body.style.overflow = prevOverflow;
      previous?.focus?.();
    };
  }, []);

  // Keyboard: capture phase on window so an enclosing <Modal> (which listens on
  // document) doesn't also close on Escape.
  React.useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.stopPropagation();
        e.preventDefault();
        onCloseRef.current();
      } else if (e.key === "ArrowRight") {
        e.stopPropagation();
        e.preventDefault();
        go(1);
      } else if (e.key === "ArrowLeft") {
        e.stopPropagation();
        e.preventDefault();
        go(-1);
      } else if (e.key === "Tab") {
        const root = dialogRef.current;
        if (!root) return;
        const focusables = Array.from(
          root.querySelectorAll<HTMLElement>('a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'),
        );
        if (focusables.length === 0) return;
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        const active = document.activeElement;
        if (e.shiftKey && (active === first || !root.contains(active))) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && (active === last || !root.contains(active))) {
          e.preventDefault();
          first.focus();
        }
        e.stopPropagation();
      }
    }
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [go]);

  if (count === 0 || typeof document === "undefined") return null;
  const url = photos[index];
  const fileName = url.split("/").pop() ?? "foto";

  return createPortal(
    <div
      ref={dialogRef}
      role="dialog"
      aria-modal="true"
      aria-label={`${title} ${index + 1} dari ${count}`}
      className="fixed inset-0 z-[60] flex flex-col bg-slate-950/90 text-white backdrop-blur-sm animate-fade-in"
    >
      {/* Top bar */}
      <div className="relative z-10 flex items-center justify-between gap-2 px-3 py-3 sm:px-5">
        <p className="text-sm font-medium tabular-nums" aria-live="polite">
          {index + 1}/{count}
        </p>
        <div className="flex items-center gap-1">
          <a
            href={url}
            download={fileName}
            className="inline-flex h-9 items-center gap-1.5 rounded-lg px-2.5 text-sm text-white/90 transition hover:bg-white/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
          >
            <Download className="h-4 w-4" />
            <span className="hidden sm:inline">Unduh</span>
          </a>
          <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex h-9 items-center gap-1.5 rounded-lg px-2.5 text-sm text-white/90 transition hover:bg-white/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
          >
            <ExternalLink className="h-4 w-4" />
            <span className="hidden sm:inline">Buka asli</span>
          </a>
          <button
            ref={closeRef}
            type="button"
            onClick={onClose}
            aria-label="Tutup"
            className="inline-flex h-9 w-9 items-center justify-center rounded-lg text-white/90 transition hover:bg-white/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
      </div>

      {/* Image area — clicking the backdrop (not the image) closes. */}
      <div
        className="relative flex min-h-0 flex-1 items-center justify-center px-2 pb-4 sm:px-16"
        onClick={(e) => {
          if (e.target === e.currentTarget) onClose();
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          key={url}
          src={url}
          alt={`${title} ${index + 1} dari ${count}`}
          className="max-h-full max-w-full select-none rounded-lg object-contain shadow-2xl"
          draggable={false}
        />

        {count > 1 && (
          <>
            <button
              type="button"
              onClick={() => go(-1)}
              aria-label="Foto sebelumnya"
              className="absolute left-2 top-1/2 inline-flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full bg-black/40 text-white transition hover:bg-black/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60 sm:left-4"
            >
              <ChevronLeft className="h-6 w-6" />
            </button>
            <button
              type="button"
              onClick={() => go(1)}
              aria-label="Foto berikutnya"
              className="absolute right-2 top-1/2 inline-flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full bg-black/40 text-white transition hover:bg-black/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60 sm:right-4"
            >
              <ChevronRight className="h-6 w-6" />
            </button>
          </>
        )}
      </div>

      {/* Thumbnail strip */}
      {count > 1 && (
        <div className="flex justify-center gap-2 px-3 pb-4">
          {photos.map((p, i) => (
            <button
              key={p}
              type="button"
              onClick={() => setIndex(i)}
              aria-label={`Lihat foto ${i + 1}`}
              aria-current={i === index ? "true" : undefined}
              className={cn(
                "h-12 w-12 overflow-hidden rounded-md border-2 transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60",
                i === index ? "border-white" : "border-transparent opacity-60 hover:opacity-100",
              )}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={p} alt="" loading="lazy" decoding="async" className="h-full w-full object-cover" />
            </button>
          ))}
        </div>
      )}
    </div>,
    document.body,
  );
}

/**
 * Small "📎 3" badge for list rows; opens the viewer on click. Renders nothing when
 * the transaction has no photos, so it can be dropped into any row unconditionally.
 */
export function PhotoBadge({ photos, className }: { photos: readonly string[]; className?: string }) {
  const [open, setOpen] = React.useState(false);
  if (photos.length === 0) return null;
  return (
    <>
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation();
          setOpen(true);
        }}
        aria-label={`Lihat ${photos.length} foto`}
        title={`${photos.length} foto`}
        className={cn(
          "inline-flex items-center gap-1 rounded-full bg-primary-soft px-2 py-0.5 text-xs font-medium text-primary transition hover:brightness-95 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
          className,
        )}
      >
        <Paperclip className="h-3 w-3" aria-hidden />
        {photos.length}
      </button>
      {open && <PhotoViewer photos={photos} onClose={() => setOpen(false)} />}
    </>
  );
}
