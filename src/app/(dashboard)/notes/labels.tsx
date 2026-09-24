"use client";

import * as React from "react";
import { ArrowDown, ArrowUp, Check, Loader2, Pin, PinOff, Plus, Trash2 } from "lucide-react";
import { SavingHint } from "@/components/ui/saving-hint";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { LABEL_NAME_MAX, NOTE_LABELS_MAX, labelNameTaken } from "@/lib/notes";
import { cn } from "@/lib/utils";
import { createNoteLabel, deleteNoteLabel, reorderNoteLabels, updateNoteLabel } from "./actions";
import { LABEL_COLORS, type NoteDTO, type NoteLabelDTO, type PushToast } from "./shared";

export function LabelChip({ label, onClick, className }: { label: NoteLabelDTO; onClick?: () => void; className?: string }) {
  const Cmp = onClick ? "button" : "span";
  return (
    <Cmp
      {...(onClick
        ? {
            type: "button" as const,
            onClick: (e: React.MouseEvent) => {
              e.stopPropagation();
              onClick();
            },
          }
        : {})}
      className={cn(
        "inline-flex max-w-full items-center gap-1 rounded-full bg-black/[0.06] px-2 py-0.5 text-xs font-medium text-foreground/80",
        onClick && "hover:bg-black/10",
        className,
      )}
    >
      <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: label.color }} />
      <span className="truncate">{label.name}</span>
    </Cmp>
  );
}

/** Popover: tick labels for a note, filter by typing, create a new one. */
export function LabelPicker({
  labels,
  selected,
  onChange,
  toast,
  onClose,
}: {
  labels: NoteLabelDTO[];
  selected: string[];
  onChange: (ids: string[]) => void;
  toast: PushToast;
  onClose: () => void;
}) {
  const [q, setQ] = React.useState("");
  const [creating, setCreating] = React.useState(false);
  const boxRef = React.useRef<HTMLDivElement>(null);
  const name = q.trim();
  const shown = labels.filter((l) => !name || l.name.toLocaleLowerCase("id-ID").includes(name.toLocaleLowerCase("id-ID")));
  const canCreate = name.length > 0 && name.length <= LABEL_NAME_MAX && !labelNameTaken(labels, name);

  React.useEffect(() => {
    function onDown(e: PointerEvent) {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) onClose();
    }
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [onClose]);

  function toggle(id: string) {
    if (selected.includes(id)) onChange(selected.filter((x) => x !== id));
    else if (selected.length >= NOTE_LABELS_MAX) toast({ text: `Maksimal ${NOTE_LABELS_MAX} label per catatan`, tone: "error" });
    else onChange([...selected, id]);
  }

  async function create() {
    if (!canCreate || creating) return;
    setCreating(true);
    const color = LABEL_COLORS[labels.length % LABEL_COLORS.length];
    const res = await createNoteLabel({ name, color }).catch(() => ({ ok: false as const, error: "Gagal membuat label" }));
    setCreating(false);
    if (!res.ok) return toast({ text: res.error, tone: "error" });
    setQ("");
    if (selected.length < NOTE_LABELS_MAX) onChange([...selected, res.id]);
  }

  return (
    <div
      ref={boxRef}
      role="dialog"
      aria-label="Pilih label"
      onKeyDown={(e) => {
        if (e.key === "Escape") {
          e.stopPropagation();
          e.nativeEvent.stopImmediatePropagation();
          onClose();
        }
      }}
      className="absolute bottom-full left-0 z-20 mb-2 w-64 max-w-[calc(100vw-2rem)] rounded-xl border border-border bg-card p-2 text-foreground shadow-xl"
    >
      <input
        autoFocus
        value={q}
        onChange={(e) => setQ(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            if (canCreate) void create();
            else if (shown.length === 1) toggle(shown[0].id);
          }
        }}
        maxLength={LABEL_NAME_MAX}
        placeholder="Cari atau buat label"
        aria-label="Cari atau buat label"
        className="mb-1 h-9 w-full rounded-lg border border-border bg-surface px-2.5 text-sm outline-none focus:border-primary"
      />
      <ul className="max-h-56 overflow-y-auto">
        {shown.map((l) => {
          const on = selected.includes(l.id);
          return (
            <li key={l.id}>
              <button
                type="button"
                role="menuitemcheckbox"
                aria-checked={on}
                onClick={() => toggle(l.id)}
                className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-accent"
              >
                <span
                  className={cn(
                    "flex h-4 w-4 shrink-0 items-center justify-center rounded border",
                    on ? "border-primary bg-primary text-white" : "border-border",
                  )}
                >
                  {on && <Check className="h-3 w-3" />}
                </span>
                <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: l.color }} />
                <span className="min-w-0 flex-1 truncate">{l.name}</span>
              </button>
            </li>
          );
        })}
        {shown.length === 0 && !canCreate && <li className="px-2 py-1.5 text-sm text-muted">Tidak ada label.</li>}
      </ul>
      {canCreate && (
        <button
          type="button"
          onClick={() => void create()}
          disabled={creating}
          aria-busy={creating || undefined}
          className="mt-1 flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm font-medium text-primary hover:bg-primary-soft disabled:opacity-60"
        >
          {creating ? <Loader2 aria-hidden className="h-4 w-4 shrink-0 animate-spin" /> : <Plus className="h-4 w-4 shrink-0" />}
          <span className="min-w-0 truncate">{creating ? "Membuat label…" : <>Buat label “{name}”</>}</span>
        </button>
      )}
    </div>
  );
}

/** Rename, recolor, pin as tab, reorder and delete labels. */
export function LabelManager({
  open,
  onClose,
  labels,
  notes,
  toast,
}: {
  open: boolean;
  onClose: () => void;
  labels: NoteLabelDTO[];
  notes: NoteDTO[];
  toast: PushToast;
}) {
  return (
    <Modal open={open} onClose={onClose} title="Kelola label" description="Label yang disematkan muncul sebagai tab." className="sm:max-w-lg">
      {open && <LabelManagerBody labels={labels} notes={notes} toast={toast} />}
    </Modal>
  );
}

function LabelManagerBody({ labels, notes, toast }: { labels: NoteLabelDTO[]; notes: NoteDTO[]; toast: PushToast }) {
  const [optimistic, apply] = React.useOptimistic(labels, (ls: NoteLabelDTO[], fn: (ls: NoteLabelDTO[]) => NoteLabelDTO[]) => fn(ls));
  const [saving, startTransition] = React.useTransition();
  const [adding, setAdding] = React.useState(false);
  const [newName, setNewName] = React.useState("");
  const [confirmDelete, setConfirmDelete] = React.useState<NoteLabelDTO | null>(null);

  const usage = React.useMemo(() => {
    const m = new Map<string, number>();
    for (const n of notes) for (const l of n.labels) m.set(l, (m.get(l) ?? 0) + 1);
    return m;
  }, [notes]);

  function run(fn: (ls: NoteLabelDTO[]) => NoteLabelDTO[], action: () => Promise<{ ok: boolean; error?: string }>) {
    startTransition(async () => {
      apply(fn);
      const res = await action().catch(() => ({ ok: false, error: "Terjadi kesalahan, coba lagi" }));
      if (!res.ok) toast({ text: res.error ?? "Gagal menyimpan label", tone: "error" });
    });
  }

  const patch = (id: string, p: Partial<NoteLabelDTO>) =>
    run(
      (ls) => ls.map((l) => (l.id === id ? { ...l, ...p } : l)),
      () => updateNoteLabel(id, p),
    );

  function move(i: number, d: -1 | 1) {
    const j = i + d;
    if (j < 0 || j >= optimistic.length) return;
    const next = optimistic.slice();
    [next[i], next[j]] = [next[j], next[i]];
    run(
      () => next.map((l, k) => ({ ...l, sortOrder: k })),
      () => reorderNoteLabels(next.map((l) => l.id)),
    );
  }

  async function add() {
    const name = newName.trim();
    if (!name || adding) return;
    setAdding(true);
    const res = await createNoteLabel({ name, color: LABEL_COLORS[labels.length % LABEL_COLORS.length] }).catch(() => ({
      ok: false as const,
      error: "Gagal membuat label",
    }));
    setAdding(false);
    if (!res.ok) toast({ text: res.error, tone: "error" });
    else setNewName("");
  }

  return (
    <div className="space-y-4">
      <form
        className="flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          void add();
        }}
      >
        <Input value={newName} onChange={(e) => setNewName(e.target.value)} maxLength={LABEL_NAME_MAX} placeholder="Label baru" aria-label="Nama label baru" />
        <Button type="submit" loading={adding} disabled={!newName.trim()}>
          {!adding && <Plus className="h-4 w-4" />} Tambah
        </Button>
        <SavingHint pending={saving} label={null} className="self-center" />
      </form>

      {optimistic.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted">Belum ada label.</p>
      ) : (
        <ul className="divide-y divide-border rounded-xl border border-border">
          {optimistic.map((l, i) => (
            <LabelRow
              key={l.id}
              label={l}
              count={usage.get(l.id) ?? 0}
              first={i === 0}
              last={i === optimistic.length - 1}
              onRename={(name) => patch(l.id, { name })}
              onColor={(color) => patch(l.id, { color })}
              onPin={() => patch(l.id, { pinnedTab: !l.pinnedTab })}
              onMove={(d) => move(i, d)}
              onDelete={() => setConfirmDelete(l)}
            />
          ))}
        </ul>
      )}

      {confirmDelete && (
        <div role="alertdialog" aria-label="Hapus label" className="rounded-xl border border-expense/30 bg-expense-soft p-3 text-sm">
          <p className="text-foreground">
            Hapus label <strong>{confirmDelete.name}</strong>?{" "}
            {(usage.get(confirmDelete.id) ?? 0) > 0
              ? `Label ini dilepas dari ${usage.get(confirmDelete.id)} catatan (catatannya tidak dihapus).`
              : "Tidak ada catatan yang memakai label ini."}
          </p>
          <div className="mt-2 flex justify-end gap-2">
            <Button variant="ghost" size="sm" onClick={() => setConfirmDelete(null)}>
              Batal
            </Button>
            <Button
              variant="danger"
              size="sm"
              onClick={() => {
                const id = confirmDelete.id;
                setConfirmDelete(null);
                run(
                  (ls) => ls.filter((x) => x.id !== id),
                  () => deleteNoteLabel(id),
                );
              }}
            >
              Hapus label
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}

function LabelRow({
  label,
  count,
  first,
  last,
  onRename,
  onColor,
  onPin,
  onMove,
  onDelete,
}: {
  label: NoteLabelDTO;
  count: number;
  first: boolean;
  last: boolean;
  onRename: (name: string) => void;
  onColor: (color: string) => void;
  onPin: () => void;
  onMove: (d: -1 | 1) => void;
  onDelete: () => void;
}) {
  const [name, setName] = React.useState(label.name);
  const [colors, setColors] = React.useState(false);
  const [prevName, setPrevName] = React.useState(label.name);
  // Follow renames that come back from the server (or a revert after an error).
  if (label.name !== prevName) {
    setPrevName(label.name);
    setName(label.name);
  }

  function commit() {
    const v = name.trim();
    if (!v) setName(label.name);
    else if (v !== label.name) onRename(v);
  }

  return (
    <li className="p-2.5">
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => setColors((v) => !v)}
          aria-label={`Warna label ${label.name}`}
          aria-expanded={colors}
          className="h-6 w-6 shrink-0 rounded-full border-2 border-white shadow ring-1 ring-border"
          style={{ background: label.color }}
        />
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === "Enter") e.currentTarget.blur();
          }}
          maxLength={LABEL_NAME_MAX}
          aria-label={`Nama label ${label.name}`}
          className="h-8 min-w-0 flex-1 rounded-md border border-transparent bg-transparent px-1.5 text-sm font-medium outline-none hover:border-border focus:border-primary"
        />
        <span className="hidden shrink-0 text-xs text-muted sm:inline">{count} catatan</span>
        <button
          type="button"
          onClick={onPin}
          aria-pressed={label.pinnedTab}
          title={label.pinnedTab ? "Lepas dari tab" : "Sematkan sebagai tab"}
          aria-label={label.pinnedTab ? `Lepas ${label.name} dari tab` : `Sematkan ${label.name} sebagai tab`}
          className={cn("shrink-0 rounded p-1.5 hover:bg-accent", label.pinnedTab ? "text-primary" : "text-muted")}
        >
          {label.pinnedTab ? <Pin className="h-4 w-4 fill-current" /> : <PinOff className="h-4 w-4" />}
        </button>
        <button type="button" onClick={() => onMove(-1)} disabled={first} aria-label={`Naikkan ${label.name}`} className="shrink-0 rounded p-1 text-muted hover:bg-accent disabled:opacity-30">
          <ArrowUp className="h-4 w-4" />
        </button>
        <button type="button" onClick={() => onMove(1)} disabled={last} aria-label={`Turunkan ${label.name}`} className="shrink-0 rounded p-1 text-muted hover:bg-accent disabled:opacity-30">
          <ArrowDown className="h-4 w-4" />
        </button>
        <button type="button" onClick={onDelete} aria-label={`Hapus label ${label.name}`} className="shrink-0 rounded p-1 text-muted hover:bg-expense-soft hover:text-expense">
          <Trash2 className="h-4 w-4" />
        </button>
      </div>
      {colors && (
        <div className="mt-2 flex flex-wrap gap-1.5 pl-8">
          {LABEL_COLORS.map((c) => (
            <button
              key={c}
              type="button"
              onClick={() => {
                onColor(c);
                setColors(false);
              }}
              aria-label={`Warna ${c}`}
              className={cn("h-6 w-6 rounded-full ring-offset-2 transition hover:scale-110", c.toLowerCase() === label.color.toLowerCase() && "ring-2 ring-primary")}
              style={{ background: c }}
            />
          ))}
        </div>
      )}
    </li>
  );
}

