"use client";

import * as React from "react";
import { FileAudio, Loader2, Square, TextQuote, Trash2, X } from "lucide-react";
import { PhotoViewer } from "@/components/photo-viewer";
import { AUDIO_RECORD_MAX_SEC, NOTE_AUDIO_MAX, NOTE_PHOTOS_MAX, TRANSCRIPT_MAX, type AudioClip } from "@/lib/notes";
import { MAX_AUDIO_BYTES } from "@/lib/media";
import { MAX_PHOTO_BYTES } from "@/lib/photos";
import { cn } from "@/lib/utils";
import { compressImage, PhotoError } from "../transactions/compress-image";
import { removeNoteMedia, setAudioTranscript, uploadNoteMedia } from "./actions";
import { formatDuration, type PushToast } from "./shared";

type Props = {
  /** The note's id, creating the note first when it doesn't exist yet. */
  ensureId: () => Promise<string | null>;
  noteId: string | null;
  photos: string[];
  audio: AudioClip[];
  toast: PushToast;
  onInsertText: (text: string) => void;
};

// ---------- Photos ----------

export function NotePhotos({ ensureId, noteId, photos, toast, pickRef }: Props & { pickRef: React.RefObject<HTMLInputElement | null> }) {
  const [busy, setBusy] = React.useState(0);
  const [viewIndex, setViewIndex] = React.useState<number | null>(null);
  const [removing, setRemoving] = React.useState<Set<string>>(() => new Set());
  const shown = photos.filter((p) => !removing.has(p));

  async function add(list: FileList | File[]) {
    const files = Array.from(list).filter((f) => {
      if (f.type.startsWith("image/")) return true;
      toast({ text: `“${f.name}” bukan file gambar.`, tone: "error" });
      return false;
    });
    const room = NOTE_PHOTOS_MAX - photos.length - busy;
    if (files.length > room) toast({ text: `Maksimal ${NOTE_PHOTOS_MAX} foto per catatan.`, tone: "error" });
    const accepted = files.slice(0, Math.max(0, room));
    if (!accepted.length) return;
    setBusy((n) => n + accepted.length);
    try {
      const compressed: File[] = [];
      for (const f of accepted) {
        try {
          compressed.push(await compressImage(f, MAX_PHOTO_BYTES));
        } catch (e) {
          toast({ text: e instanceof PhotoError ? e.message : `Gagal memproses “${f.name}”.`, tone: "error" });
        }
      }
      if (!compressed.length) return;
      const id = await ensureId();
      if (!id) return;
      // Batches under the Server Action body limit (26 MB, next.config.ts): photos the
      // browser can't re-encode (e.g. HEIC outside Safari) are sent as-is, up to 5 MB each.
      const batches: File[][] = [];
      let size = Infinity;
      for (const f of compressed) {
        if (size + f.size > 20 * 1024 * 1024) {
          batches.push([]);
          size = 0;
        }
        batches.at(-1)!.push(f);
        size += f.size;
      }
      for (const batch of batches) {
        const fd = new FormData();
        fd.set("noteId", id);
        for (const f of batch) fd.append("photos", f);
        const res = await uploadNoteMedia(fd);
        if (!res.ok) toast({ text: res.error, tone: "error" });
      }
    } catch {
      toast({ text: "Unggah foto gagal. Periksa koneksi lalu coba lagi.", tone: "error" });
    } finally {
      setBusy((n) => n - accepted.length);
    }
  }

  async function remove(url: string) {
    if (!noteId) return;
    setRemoving((s) => new Set(s).add(url));
    const res = await removeNoteMedia(noteId, url).catch(() => ({ ok: false as const, error: "Gagal menghapus foto" }));
    if (!res.ok) toast({ text: res.error, tone: "error" });
    setRemoving((s) => {
      const n = new Set(s);
      n.delete(url);
      return n;
    });
  }

  return (
    <>
      <input
        ref={pickRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={(e) => {
          const files = e.target.files ? Array.from(e.target.files) : [];
          e.target.value = "";
          void add(files);
        }}
      />
      {(shown.length > 0 || busy > 0) && (
        <div
          className="grid grid-cols-3 gap-1.5 sm:grid-cols-4"
          onDragOver={(e) => {
            if (Array.from(e.dataTransfer.types).includes("Files")) e.preventDefault();
          }}
          onDrop={(e) => {
            if (!Array.from(e.dataTransfer.types).includes("Files")) return;
            e.preventDefault();
            void add(e.dataTransfer.files);
          }}
        >
          {shown.map((url, i) => (
            <div key={url} className="group relative aspect-square overflow-hidden rounded-lg bg-black/5">
              <button
                type="button"
                onClick={() => setViewIndex(i)}
                aria-label={`Lihat foto ${i + 1}`}
                className="block h-full w-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={url} alt="" loading="lazy" decoding="async" className="h-full w-full object-cover" />
              </button>
              <button
                type="button"
                onClick={() => void remove(url)}
                aria-label={`Hapus foto ${i + 1}`}
                className="absolute right-1 top-1 rounded-full bg-slate-900/60 p-1 text-white opacity-80 transition hover:bg-slate-900/80 group-hover:opacity-100"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          ))}
          {Array.from({ length: busy }, (_, i) => (
            <div key={`busy-${i}`} className="flex aspect-square items-center justify-center rounded-lg bg-black/5 text-muted" aria-label="Mengunggah foto">
              <Loader2 className="h-5 w-5 animate-spin" />
            </div>
          ))}
        </div>
      )}
      {viewIndex !== null && (
        <PhotoViewer photos={shown} startIndex={viewIndex} title="Foto catatan" onClose={() => setViewIndex(null)} />
      )}
    </>
  );
}

// ---------- Audio ----------

/** Duration of an audio file in seconds (0 when the browser can't tell, e.g. some webm). */
function readDuration(file: Blob): Promise<number> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const a = new Audio();
    let done = false;
    const finish = (v: number) => {
      if (done) return;
      done = true;
      URL.revokeObjectURL(url);
      resolve(Number.isFinite(v) && v > 0 ? v : 0);
    };
    a.preload = "metadata";
    a.onloadedmetadata = () => {
      if (Number.isFinite(a.duration)) finish(a.duration);
      else {
        // Chrome reports Infinity for MediaRecorder webm until it seeks to the end.
        a.ondurationchange = () => Number.isFinite(a.duration) && finish(a.duration);
        a.currentTime = 1e7;
      }
    };
    a.onerror = () => finish(0);
    setTimeout(() => finish(0), 5000);
    a.src = url;
  });
}

export function NoteAudio({ ensureId, noteId, audio, toast, onInsertText, pickRef }: Props & { pickRef: React.RefObject<HTMLInputElement | null> }) {
  const [busy, setBusy] = React.useState(0);
  const [removing, setRemoving] = React.useState<Set<string>>(() => new Set());
  const shown = audio.filter((a) => !removing.has(a.url));

  async function upload(entries: { file: Blob; name: string; duration?: number }[]) {
    const room = NOTE_AUDIO_MAX - audio.length - busy;
    if (entries.length > room) toast({ text: `Maksimal ${NOTE_AUDIO_MAX} rekaman per catatan.`, tone: "error" });
    const accepted = entries.slice(0, Math.max(0, room)).filter((e) => {
      if (e.file.size > MAX_AUDIO_BYTES) {
        toast({ text: `“${e.name}” lebih dari 20 MB.`, tone: "error" });
        return false;
      }
      return true;
    });
    if (!accepted.length) return;
    setBusy((n) => n + accepted.length);
    try {
      const durations = await Promise.all(accepted.map((e) => (e.duration != null ? e.duration : readDuration(e.file))));
      const ok = accepted.filter((e, i) => {
        if (durations[i] > AUDIO_RECORD_MAX_SEC + 10) {
          toast({ text: `“${e.name}” lebih dari 10 menit.`, tone: "error" });
          return false;
        }
        return true;
      });
      if (!ok.length) return;
      const id = await ensureId();
      if (!id) return;
      // One request per clip: several 20 MB clips in one Server Action body would exceed
      // its 26 MB limit (next.config.ts) and fail as a whole.
      for (const [i, e] of accepted.entries()) {
        if (!ok.includes(e)) continue;
        const fd = new FormData();
        fd.set("noteId", id);
        fd.append("audio", e.file instanceof File ? e.file : new File([e.file], e.name, { type: e.file.type }));
        fd.append("audioDuration", String(Math.round(durations[i] * 10) / 10));
        fd.append("audioTranscript", "");
        const res = await uploadNoteMedia(fd);
        if (!res.ok) toast({ text: res.error, tone: "error" });
      }
    } catch {
      toast({ text: "Unggah rekaman gagal. Periksa koneksi lalu coba lagi.", tone: "error" });
    } finally {
      setBusy((n) => n - accepted.length);
    }
  }

  async function remove(url: string) {
    if (!noteId) return;
    setRemoving((s) => new Set(s).add(url));
    const res = await removeNoteMedia(noteId, url).catch(() => ({ ok: false as const, error: "Gagal menghapus rekaman" }));
    if (!res.ok) toast({ text: res.error, tone: "error" });
    setRemoving((s) => {
      const n = new Set(s);
      n.delete(url);
      return n;
    });
  }

  return (
    <>
      <input
        ref={pickRef}
        type="file"
        accept="audio/*,.m4a,.mp3,.aac,.ogg,.opus,.webm"
        multiple
        className="hidden"
        onChange={(e) => {
          const files = e.target.files ? Array.from(e.target.files) : [];
          e.target.value = "";
          void upload(files.map((f) => ({ file: f, name: f.name })));
        }}
      />
      {(shown.length > 0 || busy > 0) && (
        <ul className="space-y-2">
          {shown.map((clip, i) => (
            <AudioRow
              key={clip.url}
              clip={clip}
              index={i}
              noteId={noteId}
              toast={toast}
              onRemove={() => void remove(clip.url)}
              onInsertText={onInsertText}
            />
          ))}
          {Array.from({ length: busy }, (_, i) => (
            <li key={`busy-${i}`} className="flex items-center gap-2 rounded-lg bg-black/5 px-3 py-3 text-sm text-muted">
              <Loader2 className="h-4 w-4 animate-spin" /> Mengunggah rekaman…
            </li>
          ))}
        </ul>
      )}
      <RecorderSlot upload={upload} toast={toast} />
    </>
  );
}

function AudioRow({
  clip,
  index,
  noteId,
  toast,
  onRemove,
  onInsertText,
}: {
  clip: AudioClip;
  index: number;
  noteId: string | null;
  toast: PushToast;
  onRemove: () => void;
  onInsertText: (text: string) => void;
}) {
  const [editing, setEditing] = React.useState(false);
  const [text, setText] = React.useState(clip.transcript ?? "");
  const [saving, setSaving] = React.useState(false);

  async function save() {
    if (!noteId) return;
    if ((clip.transcript ?? "") === text.trim()) {
      setEditing(false);
      return;
    }
    setSaving(true);
    const res = await setAudioTranscript(noteId, clip.url, text.trim() || null).catch(() => ({
      ok: false as const,
      error: "Gagal menyimpan transkrip",
    }));
    setSaving(false);
    if (!res.ok) toast({ text: res.error, tone: "error" });
    else setEditing(false);
  }

  return (
    <li className="rounded-lg border border-black/10 bg-white/50 p-2">
      <div className="flex items-center gap-2">
        <FileAudio className="h-4 w-4 shrink-0 text-muted" aria-hidden />
        <audio controls preload="metadata" src={clip.url} className="h-9 min-w-0 flex-1" aria-label={`Rekaman ${index + 1}`} />
        <span className="shrink-0 text-xs tabular-nums text-muted">{formatDuration(clip.durationSec)}</span>
        <button
          type="button"
          onClick={onRemove}
          aria-label={`Hapus rekaman ${index + 1}`}
          className="shrink-0 rounded p-1 text-muted hover:bg-black/5 hover:text-expense"
        >
          <Trash2 className="h-4 w-4" />
        </button>
      </div>
      {editing ? (
        <div className="mt-2 space-y-2">
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            maxLength={TRANSCRIPT_MAX}
            rows={3}
            autoFocus
            placeholder="Tulis transkrip rekaman ini…"
            aria-label="Transkrip"
            className="w-full rounded-lg border border-black/10 bg-white/70 px-2 py-1.5 text-sm outline-none focus:border-primary"
          />
          <div className="flex justify-end gap-2 text-xs">
            <button
              type="button"
              onClick={() => {
                setText(clip.transcript ?? "");
                setEditing(false);
              }}
              className="rounded px-2 py-1 text-muted hover:bg-black/5"
            >
              Batal
            </button>
            <button
              type="button"
              onClick={() => void save()}
              disabled={saving}
              className="rounded bg-primary px-2.5 py-1 font-medium text-white hover:bg-primary-hover disabled:opacity-60"
            >
              {saving ? "Menyimpan…" : "Simpan transkrip"}
            </button>
          </div>
        </div>
      ) : (
        <div className="mt-1.5 flex flex-wrap items-start gap-x-3 gap-y-1 pl-6">
          {clip.transcript ? (
            <p className="w-full whitespace-pre-wrap text-sm text-foreground/80">{clip.transcript}</p>
          ) : (
            <p className="w-full text-xs text-muted-soft">Belum ada transkrip.</p>
          )}
          <button
            type="button"
            onClick={() => {
              setText(clip.transcript ?? "");
              setEditing(true);
            }}
            className="text-xs font-medium text-primary hover:underline"
          >
            {clip.transcript ? "Edit transkrip" : "Tulis transkrip"}
          </button>
          {clip.transcript && (
            <button
              type="button"
              onClick={() => onInsertText(clip.transcript!)}
              className="flex items-center gap-1 text-xs font-medium text-primary hover:underline"
            >
              <TextQuote className="h-3 w-3" /> Masukkan ke isi
            </button>
          )}
        </div>
      )}
    </li>
  );
}

// ---------- Web recording (MediaRecorder) ----------

type RecorderApi = { start: () => void };
const RecorderContext = React.createContext<{ register: (api: RecorderApi | null) => void } | null>(null);

/** Lets a toolbar button (outside NoteAudio) start a recording. */
export function RecorderProvider({ children, apiRef }: { children: React.ReactNode; apiRef: React.RefObject<RecorderApi | null> }) {
  const value = React.useMemo(
    () => ({
      register: (api: RecorderApi | null) => {
        apiRef.current = api;
      },
    }),
    [apiRef],
  );
  return <RecorderContext.Provider value={value}>{children}</RecorderContext.Provider>;
}

export function canRecord(): boolean {
  return typeof window !== "undefined" && typeof MediaRecorder !== "undefined" && !!navigator.mediaDevices?.getUserMedia;
}

function pickMime(): string | undefined {
  for (const t of ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"]) {
    if (MediaRecorder.isTypeSupported?.(t)) return t;
  }
  return undefined;
}

function RecorderSlot({
  upload,
  toast,
}: {
  upload: (e: { file: Blob; name: string; duration?: number }[]) => Promise<void>;
  toast: PushToast;
}) {
  const ctx = React.useContext(RecorderContext);
  const [state, setState] = React.useState<{ recording: boolean; elapsed: number }>({ recording: false, elapsed: 0 });
  const rec = React.useRef<{ mr: MediaRecorder; stream: MediaStream; started: number; timer: number; cancelled: boolean } | null>(null);
  const uploadRef = React.useRef(upload);
  React.useEffect(() => {
    uploadRef.current = upload;
  }, [upload]);

  const stop = React.useCallback((cancel = false) => {
    const r = rec.current;
    if (!r) return;
    r.cancelled = cancel;
    clearInterval(r.timer);
    if (r.mr.state !== "inactive") r.mr.stop();
  }, []);

  const start = React.useCallback(async () => {
    if (rec.current) return;
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      toast({ text: "Mikrofon tidak bisa diakses. Izinkan akses mikrofon di browser lalu coba lagi.", tone: "error" });
      return;
    }
    const mime = pickMime();
    const mr = new MediaRecorder(stream, { ...(mime ? { mimeType: mime } : {}), audioBitsPerSecond: 64_000 });
    const chunks: Blob[] = [];
    mr.ondataavailable = (e) => {
      if (e.data.size) chunks.push(e.data);
    };
    const started = Date.now();
    const timer = window.setInterval(() => {
      const elapsed = (Date.now() - started) / 1000;
      setState({ recording: true, elapsed });
      if (elapsed >= AUDIO_RECORD_MAX_SEC) stop();
    }, 250);
    rec.current = { mr, stream, started, timer, cancelled: false };
    mr.onstop = () => {
      const r = rec.current;
      rec.current = null;
      stream.getTracks().forEach((t) => t.stop());
      setState({ recording: false, elapsed: 0 });
      if (!r || r.cancelled || !chunks.length) return;
      const type = mr.mimeType || mime || "audio/webm";
      const ext = type.includes("mp4") ? "m4a" : type.includes("ogg") ? "ogg" : "webm";
      const duration = Math.min((Date.now() - r.started) / 1000, AUDIO_RECORD_MAX_SEC);
      const blob = new Blob(chunks, { type });
      void uploadRef.current([{ file: blob, name: `rekaman.${ext}`, duration }]);
    };
    mr.start(1000);
    setState({ recording: true, elapsed: 0 });
  }, [stop, toast]);

  React.useEffect(() => {
    ctx?.register({ start: () => void start() });
    return () => ctx?.register(null);
  }, [ctx, start]);

  // Stop (discard) when the editor closes mid-recording.
  React.useEffect(() => () => stop(true), [stop]);

  if (!state.recording) return null;
  return (
    <div className="flex items-center gap-3 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense" role="status">
      <span className="relative flex h-3 w-3">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-expense opacity-60" />
        <span className="relative inline-flex h-3 w-3 rounded-full bg-expense" />
      </span>
      <span className="font-medium">Merekam</span>
      <span className="tabular-nums">
        {formatDuration(state.elapsed)} / {formatDuration(AUDIO_RECORD_MAX_SEC)}
      </span>
      <div className="flex-1" />
      <button
        type="button"
        onClick={() => stop(true)}
        className="rounded px-2 py-1 text-xs font-medium hover:bg-expense/10"
      >
        Batal
      </button>
      <button
        type="button"
        onClick={() => stop(false)}
        className={cn("flex items-center gap-1 rounded-md bg-expense px-2.5 py-1 text-xs font-semibold text-white hover:bg-red-600")}
      >
        <Square className="h-3 w-3 fill-current" /> Selesai
      </button>
    </div>
  );
}

