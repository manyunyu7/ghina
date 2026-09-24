"use client";

import * as React from "react";
import { Link2, Plus, Trash2, X } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Input, Label, Select, Textarea } from "@/components/ui/input";
import {
  ASSET_LINKS_MAX,
  BRAND_MAX,
  CONTENT_TITLE_MAX,
  FORMATS,
  STAGES,
  type AssetLink,
  type FormatId,
  type StageId,
} from "@/lib/content";
import { CHECKLIST_MAX, isHttpUrl, NOTE_BODY_MAX, type ChecklistItem } from "@/lib/notes";
import { CURRENCIES, cn } from "@/lib/utils";
import { createContentItem, deleteContentItem, moveContentStage, updateContentItem, type ContentItemInput } from "./actions";
import { Markdown } from "./markdown";
import { usePlanner, type DialogTarget } from "./planner";
import { PhotosSection } from "./photos-section";
import { PostsSection } from "./posts-section";
import { SponsorStatus } from "./sponsor-status";
import { formatDateTime, Segmented, useToast } from "./ui";
import type { ContentItemDTO } from "./types";

type Form = {
  title: string;
  format: string;
  pillar: string;
  idea: string;
  checklist: ChecklistItem[];
  links: { key: string; url: string; label: string }[];
  hasSponsor: boolean;
  brand: string;
  amount: string;
  currency: string;
  due: string;
};

let seq = 0;
const newKey = () => `k${Date.now().toString(36)}${(++seq).toString(36)}`;

function initialForm(item: ContentItemDTO | null, currency: string): Form {
  return {
    title: item?.title ?? "",
    format: item?.format ?? "",
    pillar: item?.pillar ?? "",
    idea: item?.idea ?? "",
    checklist: item?.checklist ?? [],
    links: (item?.assetLinks ?? []).map((l) => ({ key: newKey(), url: l.url, label: l.label ?? "" })),
    hasSponsor: !!item?.sponsor,
    brand: item?.sponsor?.brand ?? "",
    amount: item?.sponsor ? String(item.sponsor.amount) : "",
    currency: item?.sponsor?.currency ?? currency,
    due: item?.sponsor?.due ?? "",
  };
}

function toInput(f: Form): { input: Omit<ContentItemInput, "stage"> } | { error: string } {
  const title = f.title.trim();
  if (!title) return { error: "Judul wajib diisi" };
  const links: AssetLink[] = [];
  for (const l of f.links) {
    const url = l.url.trim();
    if (!url && !l.label.trim()) continue;
    if (!isHttpUrl(url)) return { error: `Tautan “${url || l.label}” harus diawali http:// atau https://` };
    links.push({ url, label: l.label.trim() || null });
  }
  let sponsor: ContentItemInput["sponsor"] = null;
  if (f.hasSponsor) {
    if (!f.brand.trim()) return { error: "Nama brand sponsor wajib diisi" };
    const amount = f.amount.trim() === "" ? 0 : Number(f.amount);
    if (!Number.isFinite(amount) || amount < 0) return { error: "Nominal sponsor tidak valid" };
    sponsor = { brand: f.brand.trim(), amount, currency: f.currency, due: f.due || null };
  }
  return {
    input: {
      title,
      format: (f.format || null) as FormatId | null,
      pillar: f.pillar || null,
      idea: f.idea,
      checklist: f.checklist.filter((c) => c.text.trim()).map((c) => ({ ...c, text: c.text.trim() })),
      assetLinks: links,
      sponsor,
    },
  };
}

export function ItemDialog({ target, onClose, onCreated }: { target: DialogTarget; onClose: () => void; onCreated: (id: string) => void }) {
  const { state } = usePlanner();
  const item = target.mode === "edit" ? (state.items.find((i) => i.id === target.id) ?? null) : null;

  if (target.mode === "edit" && !item) {
    return (
      <Modal open onClose={onClose} title="Konten tidak ditemukan" description="Mungkin sudah dihapus.">
        <div className="flex justify-end">
          <Button variant="outline" onClick={onClose}>
            Tutup
          </Button>
        </div>
      </Modal>
    );
  }
  return <ItemDialogInner item={item} createStage={target.mode === "create" ? target.stage : "ide"} onClose={onClose} onCreated={onCreated} />;
}

function ItemDialogInner({
  item,
  createStage,
  onClose,
  onCreated,
}: {
  item: ContentItemDTO | null;
  createStage: StageId;
  onClose: () => void;
  onCreated: (id: string) => void;
}) {
  const { data, mutate, tz } = usePlanner();
  const toast = useToast();
  const [form, setForm] = React.useState<Form>(() => initialForm(item, data.currency));
  const [saved, setSaved] = React.useState<Form>(form);
  const [ideaMode, setIdeaMode] = React.useState<"tulis" | "pratinjau">(item?.idea ? "pratinjau" : "tulis");
  const [error, setError] = React.useState<string | null>(null);
  const [busy, setBusy] = React.useState(false);
  const [newCheck, setNewCheck] = React.useState("");
  const dirty = JSON.stringify(form) !== JSON.stringify(saved);

  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }));

  function close() {
    if (dirty && !window.confirm("Perubahan belum disimpan. Tutup tanpa menyimpan?")) return;
    onClose();
  }

  function save(e?: React.FormEvent) {
    e?.preventDefault();
    const r = toInput(form);
    if ("error" in r) {
      setError(r.error);
      return;
    }
    setError(null);
    setBusy(true);
    const snapshot = form;
    if (!item) {
      mutate(
        null,
        async () => {
          try {
            return await createContentItem({ ...r.input, stage: createStage });
          } finally {
            setBusy(false);
          }
        },
        (res) => {
          toast({ text: "Konten dibuat ✓", tone: "success" });
          onCreated(res.id);
        },
      );
      return;
    }
    mutate(
      null,
      async () => {
        try {
          return await updateContentItem(item.id, r.input);
        } finally {
          setBusy(false);
        }
      },
      () => {
        setSaved(snapshot);
        toast({ text: "Tersimpan ✓", tone: "success" });
      },
    );
  }

  function setStage(stage: StageId) {
    if (!item || stage === item.stage) return;
    mutate(
      (s) => ({ ...s, items: s.items.map((i) => (i.id === item.id ? { ...i, stage } : i)) }),
      () => moveContentStage(item.id, stage),
    );
  }

  function remove() {
    if (!item) return;
    const posts = data.posts.filter((p) => p.contentId === item.id).length;
    const msg = `Hapus “${item.title}”?${posts ? ` ${posts} posting akun ikut terhapus.` : ""}${item.sponsor?.transactionId ? " Transaksi pemasukan sponsor tetap ada." : ""}`;
    if (!window.confirm(msg)) return;
    onClose();
    mutate(
      (s) => ({ items: s.items.filter((i) => i.id !== item.id), posts: s.posts.filter((p) => p.contentId !== item.id) }),
      () => deleteContentItem(item.id),
      () => toast({ text: "Konten dihapus", tone: "info" }),
    );
  }

  const pillarOptions = data.pillars.map((p) => p.name);
  if (form.pillar && !pillarOptions.some((n) => n.toLocaleLowerCase("id-ID") === form.pillar.toLocaleLowerCase("id-ID")))
    pillarOptions.push(form.pillar);

  return (
    <Modal open onClose={close} className="sm:max-w-3xl" title={item ? undefined : "Konten baru"}>
      <form onSubmit={save} className="space-y-5">
        {/* Title + stage */}
        <div className={cn("space-y-3", item && "pr-8")}>
          <div>
            <Label htmlFor="content-title" className={item ? "sr-only" : undefined}>
              Judul
            </Label>
            <input
              id="content-title"
              value={form.title}
              onChange={(e) => set("title", e.target.value)}
              maxLength={CONTENT_TITLE_MAX}
              placeholder="Judul konten"
              autoFocus={!item}
              className="w-full rounded-lg border border-transparent bg-transparent px-1 py-1 text-xl font-bold text-foreground outline-none transition placeholder:text-muted-soft hover:border-border focus:border-primary focus:ring-2 focus:ring-primary/20"
            />
          </div>
          {item && (
            <div className="flex flex-wrap items-center gap-2">
              <div role="radiogroup" aria-label="Tahap" className="flex flex-wrap gap-1">
                {STAGES.map((s) => (
                  <button
                    key={s.id}
                    type="button"
                    role="radio"
                    aria-checked={item.stage === s.id}
                    onClick={() => setStage(s.id)}
                    className={cn(
                      "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium transition",
                      item.stage === s.id ? "border-transparent text-white" : "border-border text-muted hover:text-foreground",
                    )}
                    style={item.stage === s.id ? { background: s.color } : undefined}
                  >
                    {item.stage !== s.id && <span className="h-2 w-2 rounded-full" style={{ background: s.color }} />}
                    {s.label}
                  </button>
                ))}
              </div>
              <span className="ml-auto text-xs text-muted-soft">Diubah {formatDateTime(item.updatedAt, tz, { weekday: false })}</span>
            </div>
          )}
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Format">
            <Select value={form.format} onChange={(e) => set("format", e.target.value)}>
              <option value="">—</option>
              {FORMATS.map((f) => (
                <option key={f.id} value={f.id}>
                  {f.label}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Pilar">
            <Select value={form.pillar} onChange={(e) => set("pillar", e.target.value)}>
              <option value="">—</option>
              {pillarOptions.map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        {/* Idea (markdown) */}
        <div>
          <div className="mb-1.5 flex items-center justify-between gap-2">
            <Label className="mb-0">Ide / naskah</Label>
            <Segmented
              label="Mode ide"
              value={ideaMode}
              onChange={setIdeaMode}
              options={[
                { id: "tulis", label: "Tulis" },
                { id: "pratinjau", label: "Pratinjau" },
              ]}
              className="[&_button]:px-2 [&_button]:py-1 [&_button]:text-xs"
            />
          </div>
          {ideaMode === "tulis" ? (
            <Textarea
              value={form.idea}
              onChange={(e) => set("idea", e.target.value)}
              maxLength={NOTE_BODY_MAX}
              rows={6}
              placeholder={"Hook, poin utama, naskah…\nMarkdown: **tebal**, *miring*, - daftar, [tautan](https://…)"}
              aria-label="Ide / naskah"
            />
          ) : (
            <div
              className="min-h-20 cursor-text rounded-lg border border-border bg-surface px-3 py-2 text-sm text-foreground"
              onDoubleClick={() => setIdeaMode("tulis")}
            >
              {form.idea.trim() ? <Markdown text={form.idea} /> : <p className="text-muted-soft">Belum ada ide. Klik “Tulis”.</p>}
            </div>
          )}
        </div>

        {/* Production checklist */}
        <div>
          <Label>
            Checklist produksi{" "}
            {form.checklist.length > 0 && (
              <span className="font-normal text-muted">
                ({form.checklist.filter((c) => c.done).length}/{form.checklist.length})
              </span>
            )}
          </Label>
          <ul className="space-y-1">
            {form.checklist.map((c, i) => (
              <li key={c.id} className="group flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={c.done}
                  onChange={() => set("checklist", form.checklist.map((x) => (x.id === c.id ? { ...x, done: !x.done } : x)))}
                  className="h-4 w-4 accent-[var(--color-primary)]"
                  aria-label={`Selesai: ${c.text}`}
                />
                <input
                  value={c.text}
                  onChange={(e) => set("checklist", form.checklist.map((x) => (x.id === c.id ? { ...x, text: e.target.value } : x)))}
                  maxLength={1000}
                  aria-label={`Item checklist ${i + 1}`}
                  className={cn(
                    "h-8 min-w-0 flex-1 rounded-md border border-transparent bg-transparent px-1.5 text-sm outline-none hover:border-border focus:border-primary",
                    c.done && "text-muted line-through",
                  )}
                />
                <button
                  type="button"
                  onClick={() => set("checklist", form.checklist.filter((x) => x.id !== c.id))}
                  aria-label={`Hapus item ${c.text}`}
                  className="rounded p-1 text-muted-soft hover:bg-accent hover:text-expense"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              </li>
            ))}
          </ul>
          {form.checklist.length < CHECKLIST_MAX && (
            <div className="mt-1 flex gap-2">
              <Input
                value={newCheck}
                onChange={(e) => setNewCheck(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    addCheck();
                  }
                }}
                placeholder="Tambah langkah (mis. Rekam, Edit, Thumbnail)…"
                aria-label="Tambah item checklist"
                className="h-9"
              />
              <Button type="button" variant="outline" size="sm" className="h-9" onClick={addCheck} disabled={!newCheck.trim()}>
                <Plus className="h-4 w-4" />
              </Button>
            </div>
          )}
        </div>

        {/* Asset links */}
        <div>
          <Label>Tautan aset</Label>
          <ul className="space-y-2">
            {form.links.map((l, i) => (
              <li key={l.key} className="flex flex-wrap items-center gap-2 sm:flex-nowrap">
                <Link2 className="hidden h-4 w-4 shrink-0 text-muted-soft sm:block" />
                <Input
                  value={l.label}
                  onChange={(e) => set("links", form.links.map((x) => (x.key === l.key ? { ...x, label: e.target.value } : x)))}
                  placeholder="Label (Canva, Drive…)"
                  aria-label={`Label tautan ${i + 1}`}
                  maxLength={100}
                  className="h-9 sm:w-40"
                />
                <Input
                  value={l.url}
                  onChange={(e) => set("links", form.links.map((x) => (x.key === l.key ? { ...x, url: e.target.value } : x)))}
                  placeholder="https://"
                  inputMode="url"
                  aria-label={`URL tautan ${i + 1}`}
                  className="h-9 min-w-0 flex-1"
                />
                {isHttpUrl(l.url.trim()) && (
                  <a href={l.url.trim()} target="_blank" rel="noopener noreferrer" className="text-xs font-medium text-primary hover:underline">
                    Buka
                  </a>
                )}
                <button
                  type="button"
                  onClick={() => set("links", form.links.filter((x) => x.key !== l.key))}
                  aria-label={`Hapus tautan ${i + 1}`}
                  className="rounded p-1 text-muted-soft hover:bg-accent hover:text-expense"
                >
                  <X className="h-4 w-4" />
                </button>
              </li>
            ))}
          </ul>
          {form.links.length < ASSET_LINKS_MAX && (
            <Button type="button" variant="ghost" size="sm" className="mt-1" onClick={() => set("links", [...form.links, { key: newKey(), url: "", label: "" }])}>
              <Plus className="h-4 w-4" /> Tambah tautan
            </Button>
          )}
        </div>

        {/* Sponsor */}
        <div className="rounded-lg border border-border p-3">
          <label className="flex items-center gap-2 text-sm font-medium text-foreground">
            <input
              type="checkbox"
              checked={form.hasSponsor}
              onChange={(e) => set("hasSponsor", e.target.checked)}
              className="h-4 w-4 accent-[var(--color-primary)]"
            />
            Konten bersponsor / endorse
          </label>
          {form.hasSponsor && (
            <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-[1fr_1fr_6rem_10rem]">
              <Field label="Brand">
                <Input value={form.brand} onChange={(e) => set("brand", e.target.value)} maxLength={BRAND_MAX} placeholder="Nama brand" />
              </Field>
              <Field label="Nominal">
                <Input
                  type="number"
                  min={0}
                  step="any"
                  inputMode="decimal"
                  value={form.amount}
                  onChange={(e) => set("amount", e.target.value)}
                  placeholder="0 = barter"
                />
              </Field>
              <Field label="Mata uang">
                <Select value={form.currency} onChange={(e) => set("currency", e.target.value)}>
                  {[...new Set([form.currency, ...CURRENCIES])].map((c) => (
                    <option key={c}>{c}</option>
                  ))}
                </Select>
              </Field>
              <Field label="Jatuh tempo">
                <Input type="date" value={form.due} onChange={(e) => set("due", e.target.value)} />
              </Field>
              <p className="text-xs text-muted sm:col-span-4">Nominal 0 berarti barter (tanpa bayaran).</p>
            </div>
          )}
          {item?.sponsor && form.hasSponsor && (
            <SponsorStatus item={item} dirty={dirty} />
          )}
          {item?.sponsor && !form.hasSponsor && (
            <p className="mt-2 text-xs text-muted">
              Sponsor akan dihapus saat disimpan{item.sponsor.transactionId ? " (transaksi pemasukannya tetap ada)" : ""}.
            </p>
          )}
        </div>

        {error && (
          <p role="alert" className="rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
            {error}
          </p>
        )}

        <div className="sticky -bottom-6 z-10 -mx-6 flex flex-wrap items-center gap-2 border-t border-border bg-card px-6 py-3">
          {item && (
            <Button type="button" variant="ghost" size="sm" className="text-expense hover:bg-expense-soft hover:text-expense" onClick={remove}>
              <Trash2 className="h-4 w-4" /> Hapus
            </Button>
          )}
          <span className="ml-auto text-xs text-muted">{item ? (dirty ? "Ada perubahan belum disimpan" : "Semua tersimpan") : ""}</span>
          <Button type="button" variant="ghost" onClick={close}>
            {item ? "Tutup" : "Batal"}
          </Button>
          <Button type="submit" loading={busy} disabled={(!!item && !dirty) || !form.title.trim()}>
            {busy ? "Menyimpan…" : item ? "Simpan perubahan" : "Buat konten"}
          </Button>
        </div>
      </form>

      {item ? (
        <div className="mt-6 space-y-6">
          <PhotosSection item={item} />
          <PostsSection item={item} />
        </div>
      ) : (
        <p className="mt-4 text-xs text-muted">Setelah dibuat kamu bisa menambah foto dan posting per akun (caption, jadwal, performa).</p>
      )}
    </Modal>
  );

  function addCheck() {
    const t = newCheck.trim();
    if (!t) return;
    set("checklist", [...form.checklist, { id: crypto.randomUUID(), text: t, done: false }]);
    setNewCheck("");
  }
}
