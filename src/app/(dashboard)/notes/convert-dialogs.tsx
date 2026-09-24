"use client";

import * as React from "react";
import { Loader2 } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Input, Label, Select } from "@/components/ui/input";
import { BUCKETS, DEFAULT_BUCKET, type BucketId } from "@/lib/tasks";
import { MAX_TRANSACTION_PHOTOS } from "@/lib/photos";
import { cn } from "@/lib/utils";
import {
  convertNoteToContent,
  convertNoteToTask,
  createTransactionFromNote,
  getNoteConversion,
  type NoteConversionPrefill,
} from "./actions";
import { todayKey, type ConvertContext, type PushToast } from "./shared";

export type ConvertKind = "task" | "content" | "transaction";

const TITLES: Record<ConvertKind, string> = {
  task: "Jadikan tugas",
  content: "Jadikan konten",
  transaction: "Catat transaksi",
};

/**
 * Convert dialogs (docs/notes.md "Convert to action"). The prefill comes from the server
 * (`getNoteConversion`) so it matches what mobile shows. `ensureSaved` flushes the
 * editor's pending autosave first so the conversion sees the latest text.
 */
export function ConvertDialog({
  kind,
  noteId,
  ctx,
  ensureSaved,
  onClose,
  toast,
}: {
  kind: ConvertKind | null;
  noteId: string | null;
  ctx: ConvertContext;
  ensureSaved: () => Promise<string | null>;
  onClose: () => void;
  toast: PushToast;
}) {
  return (
    <Modal open={!!kind} onClose={onClose} title={kind ? TITLES[kind] : undefined}>
      {kind && <ConvertBody key={`${kind}-${noteId}`} kind={kind} ctx={ctx} ensureSaved={ensureSaved} onClose={onClose} toast={toast} />}
    </Modal>
  );
}

function ConvertBody({
  kind,
  ctx,
  ensureSaved,
  onClose,
  toast,
}: {
  kind: ConvertKind;
  ctx: ConvertContext;
  ensureSaved: () => Promise<string | null>;
  onClose: () => void;
  toast: PushToast;
}) {
  const [state, setState] = React.useState<{ id: string; prefill: NoteConversionPrefill } | { error: string } | null>(null);

  React.useEffect(() => {
    let alive = true;
    (async () => {
      const id = await ensureSaved();
      if (!id) {
        if (alive) setState({ error: "Tulis sesuatu di catatan dulu." });
        return;
      }
      const res = await getNoteConversion(id).catch(() => ({ ok: false as const, error: "Gagal memuat data catatan" }));
      if (!alive) return;
      setState(res.ok ? { id, prefill: res } : { error: res.error });
    })();
    return () => {
      alive = false;
    };
  }, [ensureSaved]);

  if (!state)
    return (
      <div className="flex items-center justify-center gap-2 py-10 text-sm text-muted">
        <Loader2 className="h-4 w-4 animate-spin" /> Menyiapkan…
      </div>
    );
  if ("error" in state) return <p className="py-6 text-center text-sm text-expense">{state.error}</p>;
  if (kind === "task") return <TaskForm noteId={state.id} prefill={state.prefill} ctx={ctx} onClose={onClose} toast={toast} />;
  if (kind === "content") return <ContentForm noteId={state.id} prefill={state.prefill} onClose={onClose} toast={toast} />;
  return <TransactionForm noteId={state.id} prefill={state.prefill} ctx={ctx} onClose={onClose} toast={toast} />;
}

type FormProps = { noteId: string; prefill: NoteConversionPrefill; onClose: () => void; toast: PushToast };

function Actions({ busy, label, onClose, disabled }: { busy: boolean; label: string; onClose: () => void; disabled?: boolean }) {
  return (
    <div className="flex justify-end gap-2 pt-1">
      <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
        Batal
      </Button>
      <Button type="submit" loading={busy} disabled={disabled}>
        {busy ? "Menyimpan…" : label}
      </Button>
    </div>
  );
}

function AlreadyLinked({ text, href }: { text: string; href: string }) {
  return (
    <p className="rounded-lg bg-primary-soft px-3 py-2 text-sm text-primary">
      {text}{" "}
      <a href={href} className="font-semibold underline-offset-2 hover:underline">
        Lihat →
      </a>
    </p>
  );
}

function TaskForm({ noteId, prefill, ctx, onClose, toast }: FormProps & { ctx: ConvertContext }) {
  const [title, setTitle] = React.useState(prefill.task.title);
  const [areaId, setAreaId] = React.useState(ctx.areas[0]?.id ?? "");
  const [bucket, setBucket] = React.useState<BucketId>(DEFAULT_BUCKET);
  const [busy, setBusy] = React.useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    const res = await convertNoteToTask(noteId, { areaId, bucket, title: title.trim() || prefill.task.title }).catch(() => ({
      ok: false as const,
      error: "Terjadi kesalahan, coba lagi",
    }));
    setBusy(false);
    if (!res.ok) return toast({ text: res.error, tone: "error" });
    toast({ text: "Tugas dibuat dari catatan", tone: "success", href: { label: "Buka Tugas", url: "/tasks" } });
    onClose();
  }

  if (!ctx.areas.length) return <p className="text-sm text-muted">Belum ada area tugas. Buka halaman Tugas untuk membuatnya.</p>;
  return (
    <form onSubmit={submit} className="space-y-4">
      {prefill.linkedTaskId && <AlreadyLinked text="Catatan ini sudah pernah jadi tugas." href="/tasks" />}
      <Field label="Judul tugas">
        <Input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} autoFocus />
      </Field>
      {prefill.task.note && (
        <p className="line-clamp-3 rounded-lg bg-accent px-3 py-2 text-xs text-muted">Catatan tugas: {prefill.task.note}</p>
      )}
      <Field label="Area">
        <Select value={areaId} onChange={(e) => setAreaId(e.target.value)}>
          {ctx.areas.map((a) => (
            <option key={a.id} value={a.id}>
              {a.name} ({a.code})
            </option>
          ))}
        </Select>
      </Field>
      <div>
        <Label>Prioritas</Label>
        <div className="grid grid-cols-3 gap-2" role="radiogroup" aria-label="Prioritas">
          {BUCKETS.map((b) => (
            <button
              key={b.id}
              type="button"
              role="radio"
              aria-checked={bucket === b.id}
              onClick={() => setBucket(b.id)}
              className={cn(
                "rounded-lg border px-2 py-2 text-center text-sm font-semibold transition",
                bucket === b.id ? "text-white" : "border-border bg-surface text-foreground hover:bg-accent",
              )}
              style={bucket === b.id ? { background: b.color, borderColor: b.color } : undefined}
            >
              {b.emoji} {b.label}
              <span className={cn("block text-[11px] font-normal", bucket === b.id ? "text-white/90" : "text-muted")}>{b.meaning}</span>
            </button>
          ))}
        </div>
      </div>
      <Actions busy={busy} label="Buat tugas" onClose={onClose} disabled={!areaId} />
    </form>
  );
}

function ContentForm({ noteId, prefill, onClose, toast }: FormProps) {
  const [title, setTitle] = React.useState(prefill.content.title);
  const [busy, setBusy] = React.useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    const res = await convertNoteToContent(noteId, { title: title.trim() || prefill.content.title }).catch(() => ({
      ok: false as const,
      error: "Terjadi kesalahan, coba lagi",
    }));
    setBusy(false);
    if (!res.ok) return toast({ text: res.error, tone: "error" });
    toast({
      text: "Konten dibuat di tahap Ide",
      tone: "success",
      href: { label: "Buka Konten", url: `/content?item=${encodeURIComponent(res.contentId)}` },
    });
    onClose();
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      {prefill.linkedContentId && (
        <AlreadyLinked text="Catatan ini sudah pernah jadi konten." href={`/content?item=${encodeURIComponent(prefill.linkedContentId)}`} />
      )}
      <Field label="Judul konten">
        <Input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} autoFocus />
      </Field>
      <p className="text-sm text-muted">
        Isi, checklist, dan foto catatan disalin sebagai ide konten di tahap <strong>Ide</strong>.
      </p>
      <Actions busy={busy} label="Buat konten" onClose={onClose} />
    </form>
  );
}

function TransactionForm({ noteId, prefill, ctx, onClose, toast }: FormProps & { ctx: ConvertContext }) {
  const p = prefill.transaction;
  const [type, setType] = React.useState<"expense" | "income">("expense");
  const [amount, setAmount] = React.useState(p.amount != null ? String(p.amount) : "");
  const [walletId, setWalletId] = React.useState(ctx.wallets[0]?.id ?? "");
  const [categoryId, setCategoryId] = React.useState("");
  const [note, setNote] = React.useState(p.note);
  const [date, setDate] = React.useState(todayKey);
  const [photos, setPhotos] = React.useState(p.photos.length > 0);
  const [busy, setBusy] = React.useState(false);
  const cats = ctx.categories.filter((c) => c.type === type);
  const value = Number(amount);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!(value > 0)) return toast({ text: "Nominal harus lebih dari 0", tone: "error" });
    setBusy(true);
    const res = await createTransactionFromNote(noteId, {
      type,
      amount: value,
      walletId,
      categoryId: categoryId || null,
      note: note.trim() || null,
      date,
      photos: photos ? p.photos.slice(0, MAX_TRANSACTION_PHOTOS) : [],
    }).catch(() => ({ ok: false as const, error: "Terjadi kesalahan, coba lagi" }));
    setBusy(false);
    if (!res.ok) return toast({ text: res.error, tone: "error" });
    toast({ text: type === "expense" ? "Pengeluaran dicatat" : "Pemasukan dicatat", tone: "success", href: { label: "Lihat", url: "/transactions" } });
    onClose();
  }

  if (!ctx.wallets.length) return <p className="text-sm text-muted">Belum ada dompet. Buat dompet dulu di halaman Wallets.</p>;
  return (
    <form onSubmit={submit} className="space-y-4">
      {prefill.linkedTransactionId && <AlreadyLinked text="Catatan ini sudah pernah dicatat sebagai transaksi." href="/transactions" />}
      <div className="grid grid-cols-2 gap-2 rounded-lg bg-accent p-1" role="radiogroup" aria-label="Jenis transaksi">
        {(["expense", "income"] as const).map((t) => (
          <button
            key={t}
            type="button"
            role="radio"
            aria-checked={type === t}
            onClick={() => {
              setType(t);
              setCategoryId("");
            }}
            className={cn(
              "rounded-md py-1.5 text-sm font-medium transition",
              type === t ? (t === "expense" ? "bg-surface text-expense shadow-sm" : "bg-surface text-income shadow-sm") : "text-muted",
            )}
          >
            {t === "expense" ? "Pengeluaran" : "Pemasukan"}
          </button>
        ))}
      </div>
      <Field label={`Nominal (${ctx.currency})`}>
        <Input
          type="number"
          inputMode="decimal"
          min="0"
          step="any"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0"
          autoFocus={p.amount == null}
          required
        />
        {p.amount == null && <p className="mt-1 text-xs text-muted">Nominal tidak terdeteksi dari catatan — isi manual.</p>}
      </Field>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Dompet">
          <Select value={walletId} onChange={(e) => setWalletId(e.target.value)} required>
            {ctx.wallets.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Kategori">
          <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">Tanpa kategori</option>
            {cats.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </Field>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Keterangan">
          <Input value={note} onChange={(e) => setNote(e.target.value)} maxLength={200} />
        </Field>
        <Field label="Tanggal">
          <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
        </Field>
      </div>
      {p.photos.length > 0 && (
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={photos} onChange={(e) => setPhotos(e.target.checked)} className="h-4 w-4 accent-primary" />
          Lampirkan {Math.min(p.photos.length, MAX_TRANSACTION_PHOTOS)} foto catatan
        </label>
      )}
      <Actions busy={busy} label="Simpan transaksi" onClose={onClose} disabled={!walletId} />
    </form>
  );
}
