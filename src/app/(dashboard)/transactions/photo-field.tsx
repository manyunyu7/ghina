"use client";

import * as React from "react";
import { ChevronLeft, ChevronRight, ImagePlus, Loader2, X } from "lucide-react";
import { MAX_PHOTO_BYTES, MAX_TRANSACTION_PHOTOS } from "@/lib/photos";
import { PhotoViewer } from "@/components/photo-viewer";
import { cn } from "@/lib/utils";
import { compressImage, PhotoError } from "./compress-image";

/** An already-saved photo (URL) or a new, compressed file waiting to be uploaded. */
export type PhotoItem =
  | { kind: "existing"; key: string; url: string }
  | { kind: "new"; key: string; file: File; url: string /* object URL */ };

export function initialPhotoItems(urls: readonly string[] | undefined): PhotoItem[] {
  return (urls ?? []).map((url) => ({ kind: "existing", key: url, url }));
}

/**
 * "Foto (maks 5)" section of the transaction form. Controlled: the parent owns the
 * list and appends `photos` / `keepPhotos` to the FormData on submit. Saved photos
 * always come before new ones (that's the order the server stores them in), so the
 * arrows only move a photo within its own group.
 */
export function PhotoField({
  items,
  onChange,
  onBusyChange,
  disabled,
}: {
  items: PhotoItem[];
  onChange: (next: PhotoItem[]) => void;
  onBusyChange?: (busy: boolean) => void;
  disabled?: boolean;
}) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [processing, setProcessing] = React.useState(0);
  const [errors, setErrors] = React.useState<string[]>([]);
  const [dragOver, setDragOver] = React.useState(false);
  const [viewIndex, setViewIndex] = React.useState<number | null>(null);
  const itemsRef = React.useRef(items);
  React.useEffect(() => {
    itemsRef.current = items;
  }, [items]);

  // Object URLs we created and haven't revoked yet — revoke them all on unmount.
  const objectUrls = React.useRef(new Set<string>());
  React.useEffect(() => {
    const urls = objectUrls.current;
    return () => {
      for (const u of urls) URL.revokeObjectURL(u);
      urls.clear();
    };
  }, []);

  React.useEffect(() => {
    onBusyChange?.(processing > 0);
  }, [processing, onBusyChange]);

  const remaining = MAX_TRANSACTION_PHOTOS - items.length - processing;
  const full = remaining <= 0;

  async function addFiles(list: FileList | File[]) {
    const files = Array.from(list);
    if (files.length === 0) return;
    const errs: string[] = [];
    const images = files.filter((f) => {
      if (f.type.startsWith("image/")) return true;
      errs.push(`“${f.name}” bukan file gambar.`);
      return false;
    });
    const accepted = images.slice(0, Math.max(0, remaining));
    if (images.length > accepted.length) {
      errs.push(
        `Maksimal ${MAX_TRANSACTION_PHOTOS} foto per transaksi — ${images.length - accepted.length} foto tidak ditambahkan.`,
      );
    }
    setErrors(errs);
    if (accepted.length === 0) return;

    setProcessing((n) => n + accepted.length);
    const results = await Promise.all(
      accepted.map(async (f): Promise<PhotoItem | null> => {
        try {
          const file = await compressImage(f, MAX_PHOTO_BYTES);
          const url = URL.createObjectURL(file);
          objectUrls.current.add(url);
          return { kind: "new", key: url, file, url };
        } catch (e) {
          errs.push(e instanceof PhotoError ? e.message : `Gagal memproses “${f.name}”.`);
          return null;
        }
      }),
    );
    setProcessing((n) => n - accepted.length);
    setErrors([...errs]);
    const added = results.filter((x): x is PhotoItem => x !== null);
    // Read the latest list: other adds may have finished in the meantime.
    if (added.length > 0) onChange([...itemsRef.current, ...added].slice(0, MAX_TRANSACTION_PHOTOS));
  }

  function remove(key: string) {
    const item = items.find((i) => i.key === key);
    if (item?.kind === "new") {
      URL.revokeObjectURL(item.url);
      objectUrls.current.delete(item.url);
    }
    onChange(items.filter((i) => i.key !== key));
  }

  function move(index: number, delta: -1 | 1) {
    const j = index + delta;
    if (j < 0 || j >= items.length || items[j].kind !== items[index].kind) return;
    const next = items.slice();
    [next[index], next[j]] = [next[j], next[index]];
    onChange(next);
  }

  return (
    <div
      className={cn(
        "rounded-lg border border-dashed p-3 transition",
        dragOver ? "border-primary bg-primary-soft/60" : "border-border bg-background",
      )}
      onDragOver={(e) => {
        if (disabled || !Array.from(e.dataTransfer.types).includes("Files")) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = full ? "none" : "copy";
        setDragOver(true);
      }}
      onDragLeave={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragOver(false);
      }}
      onDrop={(e) => {
        if (disabled || !Array.from(e.dataTransfer.types).includes("Files")) return;
        e.preventDefault();
        setDragOver(false);
        if (full) {
          setErrors([`Maksimal ${MAX_TRANSACTION_PHOTOS} foto per transaksi.`]);
          return;
        }
        void addFiles(e.dataTransfer.files);
      }}
    >
      <div className="flex flex-wrap gap-2">
        {items.map((item, i) => {
          const canLeft = i > 0 && items[i - 1].kind === item.kind;
          const canRight = i < items.length - 1 && items[i + 1].kind === item.kind;
          return (
            <div
              key={item.key}
              className="group relative h-20 w-20 overflow-hidden rounded-lg border border-border bg-accent"
            >
              <button
                type="button"
                onClick={() => setViewIndex(i)}
                aria-label={`Lihat foto ${i + 1}`}
                className="block h-full w-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={item.url} alt="" loading="lazy" decoding="async" className="h-full w-full object-cover" />
              </button>
              {item.kind === "new" && (
                <span className="pointer-events-none absolute left-1 top-1 rounded bg-primary px-1 text-[10px] font-semibold text-white">
                  Baru
                </span>
              )}
              <button
                type="button"
                onClick={() => remove(item.key)}
                disabled={disabled}
                aria-label={`Hapus foto ${i + 1}`}
                className="absolute right-1 top-1 rounded-full bg-slate-900/60 p-1 text-white transition hover:bg-slate-900/80"
              >
                <X className="h-3 w-3" />
              </button>
              {(canLeft || canRight) && (
                <div className="absolute inset-x-1 bottom-1 flex justify-between">
                  <button
                    type="button"
                    onClick={() => move(i, -1)}
                    disabled={disabled || !canLeft}
                    aria-label={`Geser foto ${i + 1} ke kiri`}
                    className="rounded-full bg-slate-900/60 p-0.5 text-white transition hover:bg-slate-900/80 disabled:invisible"
                  >
                    <ChevronLeft className="h-3.5 w-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => move(i, 1)}
                    disabled={disabled || !canRight}
                    aria-label={`Geser foto ${i + 1} ke kanan`}
                    className="rounded-full bg-slate-900/60 p-0.5 text-white transition hover:bg-slate-900/80 disabled:invisible"
                  >
                    <ChevronRight className="h-3.5 w-3.5" />
                  </button>
                </div>
              )}
            </div>
          );
        })}

        {Array.from({ length: processing }, (_, i) => (
          <div
            key={`processing-${i}`}
            className="flex h-20 w-20 items-center justify-center rounded-lg border border-border bg-accent text-muted"
            aria-label="Memproses foto"
          >
            <Loader2 className="h-5 w-5 animate-spin" />
          </div>
        ))}

        {!full && (
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            disabled={disabled}
            className="flex h-20 w-20 flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-border bg-surface text-xs text-muted transition hover:bg-accent hover:text-foreground disabled:opacity-50"
          >
            <ImagePlus className="h-5 w-5" />
            Tambah
          </button>
        )}
      </div>

      <p className="mt-2 text-xs text-muted-soft">
        {full
          ? `Sudah ${MAX_TRANSACTION_PHOTOS} foto (maksimal).`
          : "Struk, bukti transfer, atau nota. Seret & lepas gambar ke sini, atau klik Tambah. Foto dikecilkan otomatis."}
      </p>

      {errors.length > 0 && (
        <ul role="alert" className="mt-2 space-y-0.5 text-xs text-expense">
          {errors.map((e, i) => (
            <li key={i}>{e}</li>
          ))}
        </ul>
      )}

      {/* No `name`: the parent appends the compressed files itself. */}
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={(e) => {
          const files = e.target.files ? Array.from(e.target.files) : [];
          e.target.value = ""; // allow picking the same file again
          void addFiles(files);
        }}
      />

      {viewIndex !== null && (
        <PhotoViewer photos={items.map((i) => i.url)} startIndex={viewIndex} onClose={() => setViewIndex(null)} />
      )}
    </div>
  );
}
