"use client";

import * as React from "react";
import { ChevronLeft, ChevronRight, ImagePlus, Loader2, X } from "lucide-react";
import { PhotoViewer } from "@/components/photo-viewer";
import { CONTENT_PHOTOS_MAX } from "@/lib/content";
import { MAX_PHOTO_BYTES } from "@/lib/photos";
import { compressImage, PhotoError } from "../transactions/compress-image";
import { removeContentPhoto, updateContentItem, uploadContentPhotos } from "./actions";
import { usePlanner } from "./planner";
import { useToast } from "./ui";
import type { ContentItemDTO } from "./types";

const UPLOAD_BATCH_BYTES = 20 * 1024 * 1024;

/** Thumbnails / references: compressed in the browser, uploaded immediately. */
export function PhotosSection({ item }: { item: ContentItemDTO }) {
  const { mutate } = usePlanner();
  const toast = useToast();
  const inputRef = React.useRef<HTMLInputElement>(null);
  const [processing, setProcessing] = React.useState(0);
  const [errors, setErrors] = React.useState<string[]>([]);
  const [view, setView] = React.useState<number | null>(null);
  const [dragOver, setDragOver] = React.useState(false);
  const photos = item.photos;
  const remaining = CONTENT_PHOTOS_MAX - photos.length - processing;

  async function add(list: FileList | File[]) {
    const files = Array.from(list);
    const errs: string[] = [];
    const images = files.filter((f) => (f.type.startsWith("image/") ? true : (errs.push(`“${f.name}” bukan file gambar.`), false)));
    const accepted = images.slice(0, Math.max(0, remaining));
    if (images.length > accepted.length) errs.push(`Maksimal ${CONTENT_PHOTOS_MAX} foto per konten.`);
    setErrors(errs);
    if (!accepted.length) return;
    setProcessing((n) => n + accepted.length);
    // Batches under the Server Action body limit (26 MB; 10 uncompressible photos could be ~50 MB).
    const batches: FormData[] = [];
    let size = Infinity;
    for (const f of accepted) {
      try {
        const file = await compressImage(f, MAX_PHOTO_BYTES);
        if (size + file.size > UPLOAD_BATCH_BYTES) {
          batches.push(new FormData());
          batches[batches.length - 1].set("contentId", item.id);
          size = 0;
        }
        batches[batches.length - 1].append("photos", file);
        size += file.size;
      } catch (e) {
        errs.push(e instanceof PhotoError ? e.message : `Gagal memproses “${f.name}”.`);
      }
    }
    setErrors([...errs]);
    if (!batches.length) {
      setProcessing((n) => n - accepted.length);
      return;
    }
    mutate(
      null,
      async () => {
        try {
          let res: Awaited<ReturnType<typeof uploadContentPhotos>> = { ok: false, error: "Unggah gagal" };
          for (const fd of batches) {
            res = await uploadContentPhotos(fd);
            if (!res.ok) break;
          }
          return res;
        } finally {
          setProcessing((n) => n - accepted.length);
        }
      },
      () => toast({ text: "Foto ditambahkan ✓", tone: "success" }),
    );
  }

  function remove(url: string) {
    mutate(
      (s) => ({ ...s, items: s.items.map((i) => (i.id === item.id ? { ...i, photos: i.photos.filter((u) => u !== url) } : i)) }),
      () => removeContentPhoto(item.id, url),
    );
  }

  function move(i: number, d: -1 | 1) {
    const j = i + d;
    if (j < 0 || j >= photos.length) return;
    const next = photos.slice();
    [next[i], next[j]] = [next[j], next[i]];
    mutate(
      (s) => ({ ...s, items: s.items.map((x) => (x.id === item.id ? { ...x, photos: next } : x)) }),
      () => updateContentItem(item.id, { photos: next }),
    );
  }

  return (
    <section aria-labelledby="content-photos">
      <h3 id="content-photos" className="mb-2 text-sm font-semibold text-foreground">
        Foto <span className="font-normal text-muted">({photos.length}/{CONTENT_PHOTOS_MAX})</span>
      </h3>
      <div
        className={`rounded-lg border border-dashed p-3 transition ${dragOver ? "border-primary bg-primary-soft/60" : "border-border bg-background"}`}
        onDragOver={(e) => {
          if (!Array.from(e.dataTransfer.types).includes("Files")) return;
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={(e) => {
          if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragOver(false);
        }}
        onDrop={(e) => {
          if (!Array.from(e.dataTransfer.types).includes("Files")) return;
          e.preventDefault();
          setDragOver(false);
          void add(e.dataTransfer.files);
        }}
      >
        <div className="flex flex-wrap gap-2">
          {photos.map((url, i) => (
            <div key={url} className="relative h-20 w-20 overflow-hidden rounded-lg border border-border bg-accent">
              <button type="button" onClick={() => setView(i)} aria-label={`Lihat foto ${i + 1}`} className="block h-full w-full">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={url} alt="" loading="lazy" decoding="async" className="h-full w-full object-cover" />
              </button>
              <button
                type="button"
                onClick={() => remove(url)}
                aria-label={`Hapus foto ${i + 1}`}
                className="absolute right-1 top-1 rounded-full bg-slate-900/60 p-1 text-white hover:bg-slate-900/80"
              >
                <X className="h-3 w-3" />
              </button>
              {photos.length > 1 && (
                <div className="absolute inset-x-1 bottom-1 flex justify-between">
                  <button type="button" onClick={() => move(i, -1)} disabled={i === 0} aria-label={`Geser foto ${i + 1} ke kiri`} className="rounded-full bg-slate-900/60 p-0.5 text-white disabled:invisible">
                    <ChevronLeft className="h-3.5 w-3.5" />
                  </button>
                  <button type="button" onClick={() => move(i, 1)} disabled={i === photos.length - 1} aria-label={`Geser foto ${i + 1} ke kanan`} className="rounded-full bg-slate-900/60 p-0.5 text-white disabled:invisible">
                    <ChevronRight className="h-3.5 w-3.5" />
                  </button>
                </div>
              )}
            </div>
          ))}
          {Array.from({ length: processing }, (_, i) => (
            <div key={`p${i}`} className="flex h-20 w-20 items-center justify-center rounded-lg border border-border bg-accent text-muted" aria-label="Mengunggah foto">
              <Loader2 className="h-5 w-5 animate-spin" />
            </div>
          ))}
          {remaining > 0 && (
            <button
              type="button"
              onClick={() => inputRef.current?.click()}
              className="flex h-20 w-20 flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-border bg-surface text-xs text-muted transition hover:bg-accent hover:text-foreground"
            >
              <ImagePlus className="h-5 w-5" /> Tambah
            </button>
          )}
        </div>
        <p className="mt-2 text-xs text-muted-soft">Thumbnail, referensi, atau aset. Seret gambar ke sini; foto dikecilkan otomatis dan langsung tersimpan.</p>
        {errors.length > 0 && (
          <ul role="alert" className="mt-2 space-y-0.5 text-xs text-expense">
            {errors.map((e, i) => (
              <li key={i}>{e}</li>
            ))}
          </ul>
        )}
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          multiple
          className="hidden"
          aria-label="Pilih foto"
          onChange={(e) => {
            const files = e.target.files ? Array.from(e.target.files) : [];
            e.target.value = "";
            void add(files);
          }}
        />
      </div>
      {view !== null && <PhotoViewer photos={photos} startIndex={view} onClose={() => setView(null)} title="Foto konten" />}
    </section>
  );
}
