"use client";

import * as React from "react";
import { AlertTriangle, Bot, FileText, Paperclip, RotateCcw, Send, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Select, Textarea } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/misc";
import { SavingHint } from "@/components/ui/saving-hint";
import type { KillaAttachment, KillaMessageDTO } from "@/lib/killa";
import { KILLA_MEDIA_MAX_BYTES, KILLA_MEDIA_MAX_FILES, KILLA_MODELS, KILLA_TEXT_MAX, type KillaModel } from "@/lib/schemas";
import { cn } from "@/lib/utils";
import { Markdown } from "../notes/markdown";
import { loadOlderKillaMessages, newKillaSession, sendKillaChat } from "./actions";

const MODEL_LABELS: Record<KillaModel, string> = {
  default: "Default",
  fable: "Fable",
  opus: "Opus",
  sonnet: "Sonnet",
  haiku: "Haiku",
};

const ACCEPT = "image/jpeg,image/png,image/webp,image/gif,application/pdf";
/** Poll for WhatsApp-mirrored turns while the page is visible. */
const POLL_MS = 20_000;
/** Images larger than this (bytes or px) are re-encoded client-side before sending. */
const RESIZE_OVER_BYTES = 1.5 * 1024 * 1024;
const RESIZE_MAX_PX = 2048;

const timeFmt = new Intl.DateTimeFormat("id-ID", { hour: "2-digit", minute: "2-digit" });
const dayFmt = new Intl.DateTimeFormat("id-ID", { weekday: "long", day: "numeric", month: "long", year: "numeric" });

type Pending = { id: string; file: File; preview: string | null };

/**
 * The Killa chat: recorded history (newest page from the server, older pages loaded on
 * demand, newest page re-polled every 20 s so WhatsApp-mirrored turns show up), a composer
 * with up to 3 image/PDF attachments and the "sesi baru" button. A reply can take
 * minutes, so the sent message shows optimistically with a "Killa sedang mengerjakan…"
 * bubble until it lands.
 */
export function KillaChat({ messages, nextBefore }: { messages: KillaMessageDTO[]; nextBefore: string | null }) {
  // Every message seen so far (server pages merged by id), so a revalidated newest page
  // never drops messages that were shown before or loaded via "Muat pesan lama".
  const [known, setKnown] = React.useState(messages);
  const [prevMessages, setPrevMessages] = React.useState(messages);
  if (messages !== prevMessages) {
    setPrevMessages(messages);
    setKnown((k) => mergeMessages(k, messages));
  }
  const [cursor, setCursor] = React.useState(nextBefore);
  const [loadingOlder, setLoadingOlder] = React.useState(false);
  const [all, addOptimistic] = React.useOptimistic(known, (s: KillaMessageDTO[], m: KillaMessageDTO) => [...s, m]);
  const [sending, startSend] = React.useTransition();
  const [resetting, startReset] = React.useTransition();
  const [text, setText] = React.useState("");
  const [files, setFiles] = React.useState<Pending[]>([]);
  const [preparing, setPreparing] = React.useState(false);
  const [model, setModel] = React.useState<KillaModel>("default");
  const [error, setError] = React.useState<string | null>(null);
  const listRef = React.useRef<HTMLDivElement>(null);
  const fileRef = React.useRef<HTMLInputElement>(null);
  const stickRef = React.useRef(true); // was the list scrolled to the bottom?
  const sendingRef = React.useRef(false);
  React.useEffect(() => {
    sendingRef.current = sending;
  }, [sending]);

  const lastId = all.at(-1)?.id;

  // Auto-scroll to the newest message — unless the user scrolled up to read older ones.
  React.useEffect(() => {
    const list = listRef.current;
    if (list && stickRef.current) list.scrollTop = list.scrollHeight;
  }, [lastId, sending]);

  function onScroll() {
    const list = listRef.current;
    if (list) stickRef.current = list.scrollHeight - list.scrollTop - list.clientHeight < 80;
  }

  // Poll the newest page (WA-mirrored turns) every 20 s while visible and idle.
  React.useEffect(() => {
    let stopped = false;
    async function poll() {
      if (stopped || document.visibilityState !== "visible" || sendingRef.current) return;
      try {
        const res = await fetch("/api/killa/messages?limit=30", { cache: "no-store" });
        if (!res.ok) return;
        const data = (await res.json()) as { messages?: KillaMessageDTO[] };
        if (!stopped && Array.isArray(data.messages) && data.messages.length) {
          setKnown((k) => mergeMessages(k, data.messages!));
        }
      } catch {
        /* offline — try again next tick */
      }
    }
    const t = setInterval(poll, POLL_MS);
    const onVisible = () => {
      if (document.visibilityState === "visible") void poll();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      stopped = true;
      clearInterval(t);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, []);

  async function addFiles(list: FileList | null) {
    if (!list?.length) return;
    setError(null);
    const picked = [...list];
    const room = KILLA_MEDIA_MAX_FILES - files.length;
    if (picked.length > room) setError(`Maksimal ${KILLA_MEDIA_MAX_FILES} lampiran per pesan`);
    setPreparing(true);
    const next: Pending[] = [];
    for (const raw of picked.slice(0, Math.max(0, room))) {
      if (!ACCEPT.split(",").includes(raw.type)) {
        setError("Lampiran harus gambar (JPEG, PNG, WebP, GIF) atau PDF");
        continue;
      }
      const file = raw.type.startsWith("image/") ? await shrinkImage(raw) : raw;
      if (file.size > KILLA_MEDIA_MAX_BYTES) {
        setError(`${raw.name} terlalu besar (maks 8 MB)`);
        continue;
      }
      next.push({
        id: `${Date.now()}-${Math.random()}`,
        file,
        preview: file.type.startsWith("image/") ? URL.createObjectURL(file) : null,
      });
    }
    setPreparing(false);
    setFiles((f) => [...f, ...next].slice(0, KILLA_MEDIA_MAX_FILES));
  }

  function send() {
    const body = text.trim();
    if ((!body && files.length === 0) || sending || preparing) return;
    setError(null);
    setText("");
    const sent = files;
    setFiles([]);
    stickRef.current = true;
    const form = new FormData();
    form.set("text", body);
    form.set("model", model);
    for (const p of sent) form.append("files", p.file, p.file.name);
    startSend(async () => {
      addOptimistic({
        id: `pending-${Date.now()}`,
        role: "user",
        body,
        model: model === "default" ? null : model,
        channel: "app",
        attachments: sent.map((p) => ({
          // Local preview until the recorded message (with its /uploads URL) arrives.
          path: p.preview ?? "",
          name: p.file.name,
          kind: p.preview ? "image" : "file",
          source: "upload",
        })),
        createdAt: new Date().toISOString(),
      });
      try {
        const res = await sendKillaChat(form);
        if (res.ok) setKnown((k) => mergeMessages(k, [res.userMessage, res.reply]));
        else setError(res.error);
      } catch {
        setError("Koneksi terputus. Balasan mungkin tetap tersimpan — muat ulang halaman nanti.");
      } finally {
        // The optimistic bubble used the local previews; the recorded message has /uploads URLs.
        for (const p of sent) if (p.preview) URL.revokeObjectURL(p.preview);
      }
    });
  }

  function reset() {
    setError(null);
    startReset(async () => {
      const res = await newKillaSession().catch(() => ({ ok: false as const, error: "Terjadi kesalahan, coba lagi" }));
      if (!res.ok) setError(res.error);
    });
  }

  async function loadOlder() {
    if (!cursor) return;
    setLoadingOlder(true);
    const list = listRef.current;
    const prevHeight = list?.scrollHeight ?? 0;
    stickRef.current = false;
    const res = await loadOlderKillaMessages(cursor).catch(() => null);
    setLoadingOlder(false);
    if (!res?.ok) {
      setError(res?.error ?? "Gagal memuat pesan lama");
      return;
    }
    setKnown((k) => mergeMessages(k, res.messages));
    setCursor(res.nextBefore);
    // Keep the view anchored on the message that was at the top.
    requestAnimationFrame(() => {
      if (list) list.scrollTop += list.scrollHeight - prevHeight;
    });
  }

  const canSend = (text.trim().length > 0 || files.length > 0) && !preparing;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <label htmlFor="killa-model" className="text-sm font-medium text-muted">
            Model
          </label>
          <Select
            id="killa-model"
            value={model}
            onChange={(e) => setModel(e.target.value as KillaModel)}
            className="h-9 w-32"
            disabled={sending}
          >
            {KILLA_MODELS.map((m) => (
              <option key={m} value={m}>
                {MODEL_LABELS[m]}
              </option>
            ))}
          </Select>
        </div>
        <div className="flex items-center gap-2">
          <SavingHint pending={resetting} label="Memulai sesi…" />
          <Button variant="outline" size="sm" onClick={reset} loading={resetting} disabled={sending}>
            {!resetting && <RotateCcw className="h-4 w-4" />} Sesi baru
          </Button>
        </div>
      </div>

      <Card className="overflow-hidden">
        <div ref={listRef} onScroll={onScroll} className="max-h-[60vh] min-h-64 space-y-3 overflow-y-auto p-4">
          {cursor && (
            <div className="flex justify-center">
              <Button variant="ghost" size="sm" onClick={loadOlder} loading={loadingOlder}>
                Muat pesan lama
              </Button>
            </div>
          )}
          {all.length === 0 && !sending ? (
            <EmptyState icon={Bot} title="Belum ada percakapan" description="Tulis pesan untuk mulai ngobrol dengan Killa." />
          ) : (
            all.map((m, i) => {
              const day = dayKey(m.createdAt);
              const newDay = i === 0 || dayKey(all[i - 1].createdAt) !== day;
              return (
                <React.Fragment key={m.id}>
                  {newDay && <DaySeparator iso={m.createdAt} />}
                  <MessageRow m={m} />
                </React.Fragment>
              );
            })
          )}
          {sending && <ThinkingBubble />}
        </div>
      </Card>

      {error && (
        <div role="alert" className="flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {(files.length > 0 || preparing) && (
        <div className="flex flex-wrap items-center gap-2">
          {files.map((p) => (
            <div key={p.id} className="relative flex items-center gap-2 rounded-lg border border-border bg-card p-1.5 pr-8 text-xs">
              {p.preview ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={p.preview} alt="" className="h-10 w-10 rounded object-cover" />
              ) : (
                <FileText className="h-5 w-5 text-muted" />
              )}
              <span className="max-w-40 truncate text-foreground">{p.file.name}</span>
              <button
                type="button"
                onClick={() => {
                  if (p.preview) URL.revokeObjectURL(p.preview);
                  setFiles((f) => f.filter((x) => x.id !== p.id));
                }}
                className="absolute right-1.5 top-1/2 -translate-y-1/2 rounded p-0.5 text-muted hover:bg-accent hover:text-foreground"
                aria-label={`Hapus ${p.file.name}`}
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          ))}
          {preparing && <SavingHint pending label="Menyiapkan lampiran…" className="text-xs" />}
        </div>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          send();
        }}
        className="flex items-end gap-2"
      >
        <input
          ref={fileRef}
          type="file"
          accept={ACCEPT}
          multiple
          hidden
          onChange={(e) => {
            void addFiles(e.target.files);
            e.target.value = "";
          }}
        />
        <Button
          type="button"
          variant="outline"
          size="icon"
          className="h-11 w-11 shrink-0"
          onClick={() => fileRef.current?.click()}
          disabled={sending || preparing || files.length >= KILLA_MEDIA_MAX_FILES}
          aria-label="Lampirkan gambar atau PDF"
          title="Lampirkan gambar atau PDF (maks 3, 8 MB)"
        >
          <Paperclip className="h-4 w-4" />
        </Button>
        <Textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault();
              send();
            }
          }}
          onPaste={(e) => {
            if (e.clipboardData.files.length) {
              e.preventDefault();
              void addFiles(e.clipboardData.files);
            }
          }}
          placeholder="Tulis pesan untuk Killa… (Enter kirim, Shift+Enter baris baru)"
          maxLength={KILLA_TEXT_MAX}
          rows={2}
          className="max-h-60 min-h-11 flex-1 resize-y"
          aria-label="Pesan"
        />
        <Button type="submit" size="icon" className="h-11 w-11 shrink-0" loading={sending} disabled={!canSend} aria-label="Kirim">
          <Send className="h-4 w-4" />
        </Button>
      </form>
    </div>
  );
}

function mergeMessages(a: KillaMessageDTO[], b: KillaMessageDTO[]): KillaMessageDTO[] {
  const byId = new Map(a.map((m) => [m.id, m]));
  for (const m of b) byId.set(m.id, m);
  return [...byId.values()].sort((x, y) => x.createdAt.localeCompare(y.createdAt) || x.id.localeCompare(y.id));
}

function dayKey(iso: string) {
  const d = new Date(iso);
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function DaySeparator({ iso }: { iso: string }) {
  const d = new Date(iso);
  const today = new Date();
  const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
  const label =
    dayKey(iso) === dayKey(today.toISOString())
      ? "Hari ini"
      : dayKey(iso) === dayKey(yesterday.toISOString())
        ? "Kemarin"
        : dayFmt.format(d);
  return (
    <div className="flex justify-center py-1">
      <span className="rounded-full bg-accent px-3 py-0.5 text-[11px] font-medium text-muted">{label}</span>
    </div>
  );
}

/** Where an attachment is served from: /uploads directly, engine files via the proxy. */
function attachmentSrc(a: KillaAttachment) {
  return a.source === "upload" ? a.path : `/api/killa/media?path=${encodeURIComponent(a.path)}`;
}

function Attachments({ items, me }: { items: KillaAttachment[]; me: boolean }) {
  if (!items.length) return null;
  return (
    <div className="mt-2 flex flex-wrap gap-2">
      {items.map((a, i) =>
        a.kind === "image" && a.path ? (
          <a key={i} href={attachmentSrc(a)} target="_blank" rel="noopener noreferrer" className="block">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={attachmentSrc(a)}
              alt={a.name}
              loading="lazy"
              className="max-h-60 max-w-full rounded-lg border border-black/10 object-contain"
            />
          </a>
        ) : (
          <a
            key={i}
            href={a.path ? attachmentSrc(a) : undefined}
            target="_blank"
            rel="noopener noreferrer"
            download={a.source === "engine" && !/\.pdf$/i.test(a.name) ? a.name : undefined}
            className={cn(
              "inline-flex max-w-full items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium",
              me ? "bg-white/15 text-white hover:bg-white/25" : "bg-card text-foreground hover:bg-card/70",
            )}
          >
            <FileText className="h-4 w-4 shrink-0" />
            <span className="truncate">{a.name}</span>
          </a>
        ),
      )}
    </div>
  );
}

function MessageRow({ m }: { m: KillaMessageDTO }) {
  const time = timeFmt.format(new Date(m.createdAt));
  if (m.role === "system") {
    return (
      <div className="flex items-center gap-3 py-1 text-xs font-medium text-muted">
        <div className="h-px flex-1 bg-border" />
        <span>
          {m.body} · {time}
        </span>
        <div className="h-px flex-1 bg-border" />
      </div>
    );
  }
  const me = m.role === "user";
  return (
    <div className={cn("flex", me ? "justify-end" : "justify-start")}>
      <div
        className={cn(
          "max-w-[85%] rounded-2xl px-3.5 py-2.5",
          me ? "rounded-br-md bg-primary text-white" : "rounded-bl-md bg-accent text-foreground",
          m.id.startsWith("pending-") && "opacity-70",
        )}
      >
        {m.body &&
          (me ? (
            <p className="whitespace-pre-wrap break-words text-sm leading-relaxed">{m.body}</p>
          ) : (
            <Markdown text={m.body} />
          ))}
        <Attachments items={m.attachments} me={me} />
        <p className={cn("mt-1 flex items-center gap-1.5 text-[11px]", me ? "text-white/70" : "text-muted")}>
          {m.channel === "wa" && (
            <span
              title="Dari WhatsApp"
              className={cn(
                "rounded px-1 py-px text-[10px] font-semibold leading-none",
                me ? "bg-white/20 text-white" : "bg-income-soft text-income",
              )}
            >
              WA
            </span>
          )}
          <span>
            {time}
            {m.model ? ` · ${m.model}` : ""}
          </span>
        </p>
      </div>
    </div>
  );
}

/** Shown while a reply is on its way, with elapsed time (replies can take minutes). */
function ThinkingBubble() {
  const [secs, setSecs] = React.useState(0);
  React.useEffect(() => {
    const t = setInterval(() => setSecs((s) => s + 1), 1000);
    return () => clearInterval(t);
  }, []);
  const elapsed = secs >= 60 ? `${Math.floor(secs / 60)}m ${secs % 60}d` : `${secs}d`;
  return (
    <div className="flex justify-start">
      <div className="rounded-2xl rounded-bl-md bg-accent px-3.5 py-2.5">
        <SavingHint pending label={`Killa sedang mengerjakan… ${elapsed}`} className="text-sm" />
      </div>
    </div>
  );
}

/**
 * Re-encode a large photo as JPEG ≤ 2048 px (keeps uploads and the engine prompt small).
 * GIFs (may be animated) and small images are sent as-is; any failure falls back to the
 * original file.
 */
async function shrinkImage(file: File): Promise<File> {
  if (file.type === "image/gif") return file;
  try {
    const bmp = await createImageBitmap(file);
    const scale = Math.min(1, RESIZE_MAX_PX / Math.max(bmp.width, bmp.height));
    if (scale === 1 && file.size <= RESIZE_OVER_BYTES) {
      bmp.close();
      return file;
    }
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(bmp.width * scale);
    canvas.height = Math.round(bmp.height * scale);
    const ctx = canvas.getContext("2d");
    if (!ctx) return file;
    ctx.fillStyle = "#fff"; // PNG transparency → white instead of black in JPEG
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(bmp, 0, 0, canvas.width, canvas.height);
    bmp.close();
    const blob = await new Promise<Blob | null>((r) => canvas.toBlob(r, "image/jpeg", 0.85));
    if (!blob || blob.size >= file.size) return file;
    return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".jpg", { type: "image/jpeg" });
  } catch {
    return file;
  }
}
