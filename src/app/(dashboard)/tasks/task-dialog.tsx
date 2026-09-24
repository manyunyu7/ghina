"use client";

import * as React from "react";
import { AlertTriangle, Trash2 } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Input, Label, Select, Textarea } from "@/components/ui/input";
import {
  BUCKETS,
  REMIND_BEFORE_OPTIONS,
  TASK_NOTE_MAX,
  TASK_TITLE_MAX,
  isoWeekday,
  type BucketId,
  type Recurrence,
  type RecurrenceFreq,
} from "@/lib/tasks";
import { cn, formatCurrency } from "@/lib/utils";
import { createTask, deleteTask, updateTask, type TaskInput } from "./actions";
import { WEEKDAYS_LONG, WEEKDAYS_SHORT, errorText, recurrenceLabel, remindLabel } from "./format";
import type { AreaDTO, CategoryOption, TaskDTO, WalletOption } from "./types";

export type TaskDialogTarget = { mode: "create"; areaId: string; bucket: BucketId } | { mode: "edit"; task: TaskDTO };

type Form = {
  title: string;
  note: string;
  areaId: string;
  bucket: BucketId;
  dueDate: string;
  dueTime: string;
  remind: string; // "" = none
  freq: "" | RecurrenceFreq;
  interval: string;
  weekdays: number[];
  monthDay: string;
  money: boolean;
  amount: string;
  walletId: string;
  categoryId: string;
};

function initialForm(target: TaskDialogTarget): Form {
  if (target.mode === "create") {
    return {
      title: "",
      note: "",
      areaId: target.areaId,
      bucket: target.bucket,
      dueDate: "",
      dueTime: "",
      remind: "",
      freq: "",
      interval: "1",
      weekdays: [],
      monthDay: "",
      money: false,
      amount: "",
      walletId: "",
      categoryId: "",
    };
  }
  const t = target.task;
  return {
    title: t.title,
    note: t.note ?? "",
    areaId: t.areaId,
    bucket: t.bucket,
    dueDate: t.dueDate ?? "",
    dueTime: t.dueTime ?? "",
    remind: t.remindBefore == null ? "" : String(t.remindBefore),
    freq: t.recurrence?.freq ?? "",
    interval: String(t.recurrence?.interval ?? 1),
    weekdays: t.recurrence?.weekdays ?? [],
    monthDay: t.recurrence?.monthDay ? String(t.recurrence.monthDay) : "",
    money: t.amount != null,
    amount: t.amount != null ? String(t.amount) : "",
    walletId: t.walletId ?? "",
    categoryId: t.categoryId ?? "",
  };
}

/** Build the action payload, or a user-facing error. */
function toInput(f: Form): { input: TaskInput } | { error: string } {
  const title = f.title.trim();
  if (!title) return { error: "Judul wajib diisi" };
  if (f.dueTime && !f.dueDate) return { error: "Isi tanggal dulu sebelum jam" };

  let recurrence: Recurrence | null = null;
  if (f.freq) {
    if (!f.dueDate) return { error: "Tugas berulang perlu tanggal" };
    const interval = Number(f.interval);
    if (!Number.isInteger(interval) || interval < 1 || interval > 365) return { error: "Interval harus 1–365" };
    recurrence = { freq: f.freq, interval };
    if (f.freq === "weekly") recurrence.weekdays = f.weekdays.length ? f.weekdays : [isoWeekday(f.dueDate)];
    if (f.freq === "monthly") {
      const day = f.monthDay ? Number(f.monthDay) : Number(f.dueDate.slice(8, 10));
      if (!Number.isInteger(day) || day < 1 || day > 31) return { error: "Tanggal bulanan harus 1–31" };
      recurrence.monthDay = day;
    }
  }

  let amount: number | null = null;
  if (f.money) {
    amount = Number(f.amount);
    if (!f.amount || !Number.isFinite(amount) || amount <= 0) return { error: "Nominal harus lebih dari 0" };
  }

  return {
    input: {
      areaId: f.areaId,
      title,
      note: f.note.trim() || null,
      bucket: f.bucket,
      dueDate: f.dueDate || null,
      dueTime: f.dueDate && f.dueTime ? f.dueTime : null,
      remindBefore: f.dueDate && f.dueTime && f.remind !== "" ? Number(f.remind) : null,
      recurrence,
      amount,
      walletId: f.money ? f.walletId || null : null,
      categoryId: f.money ? f.categoryId || null : null,
    },
  };
}

export function TaskDialog({
  target,
  onClose,
  onDeleted,
  areas,
  wallets,
  categories,
  currency,
}: {
  target: TaskDialogTarget | null;
  onClose: () => void;
  /** Optimistic removal from the board, run before the delete request. */
  onDeleted: (task: TaskDTO, run: () => Promise<{ ok: boolean; error?: string }>) => void;
  areas: AreaDTO[];
  wallets: WalletOption[];
  categories: CategoryOption[];
  currency: string;
}) {
  return (
    <Modal
      open={!!target}
      onClose={onClose}
      title={target?.mode === "edit" ? "Edit tugas" : "Tugas baru"}
      className="sm:max-w-lg"
    >
      {target && (
        <TaskForm
          key={target.mode === "edit" ? target.task.id : `new-${target.areaId}-${target.bucket}`}
          target={target}
          onClose={onClose}
          onDeleted={onDeleted}
          areas={areas}
          wallets={wallets}
          categories={categories}
          currency={currency}
        />
      )}
    </Modal>
  );
}

function TaskForm({
  target,
  onClose,
  onDeleted,
  areas,
  wallets,
  categories,
  currency,
}: {
  target: TaskDialogTarget;
  onClose: () => void;
  onDeleted: (task: TaskDTO, run: () => Promise<{ ok: boolean; error?: string }>) => void;
  areas: AreaDTO[];
  wallets: WalletOption[];
  categories: CategoryOption[];
  currency: string;
}) {
  const [f, setF] = React.useState<Form>(() => initialForm(target));
  const [error, setError] = React.useState<string | null>(null);
  const [pending, setPending] = React.useState(false);
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setF((p) => ({ ...p, [k]: v }));

  // Archived areas stay selectable only for a task already in one.
  const areaOptions = areas.filter((a) => !a.archived || a.id === f.areaId);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const built = toInput(f);
    if ("error" in built) {
      setError(built.error);
      return;
    }
    setPending(true);
    setError(null);
    try {
      const res =
        target.mode === "edit" ? await updateTask(target.task.id, built.input) : await createTask(built.input);
      if (res.ok) onClose();
      else setError(errorText(res.error));
    } catch {
      setError("Terjadi kesalahan");
    } finally {
      setPending(false);
    }
  }

  const previewRule: Recurrence | null =
    f.freq && f.dueDate
      ? {
          freq: f.freq,
          interval: Math.max(1, Number(f.interval) || 1),
          ...(f.freq === "weekly" ? { weekdays: f.weekdays.length ? f.weekdays : [isoWeekday(f.dueDate)] } : {}),
          ...(f.freq === "monthly" ? { monthDay: Number(f.monthDay) || Number(f.dueDate.slice(8, 10)) } : {}),
        }
      : null;

  if (confirmDelete && target.mode === "edit") {
    const task = target.task;
    return (
      <div className="space-y-4">
        <div className="flex gap-3 rounded-lg bg-expense-soft p-3 text-expense">
          <AlertTriangle className="h-5 w-5 shrink-0" />
          <div className="text-sm">
            <p className="font-medium">Hapus tugas ini?</p>
            <p className="mt-0.5 text-expense/90">
              <span className="font-semibold">{task.title}</span> akan dihapus permanen.
              {task.recurrence && " Kejadian berikutnya yang sudah dibuat tidak ikut terhapus."}
              {task.transactionId && " Pengeluaran yang sudah tercatat tetap ada."}
            </p>
          </div>
        </div>
        {error && <p className="text-sm text-expense">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={() => setConfirmDelete(false)}>
            Batal
          </Button>
          <Button
            variant="danger"
            onClick={() => {
              onDeleted(task, () => deleteTask(task.id));
              onClose();
            }}
          >
            Hapus tugas
          </Button>
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <Field label="Judul">
        <Input
          value={f.title}
          onChange={(e) => set("title", e.target.value)}
          maxLength={TASK_TITLE_MAX}
          placeholder="Contoh: Kirim revisi client A"
          autoFocus
          required
        />
      </Field>

      <Field label="Catatan">
        <Textarea
          value={f.note}
          onChange={(e) => set("note", e.target.value)}
          maxLength={TASK_NOTE_MAX}
          placeholder="Opsional"
          rows={2}
        />
      </Field>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="Area">
          <Select value={f.areaId} onChange={(e) => set("areaId", e.target.value)}>
            {areaOptions.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name} ({a.code}){a.archived ? " — diarsipkan" : ""}
              </option>
            ))}
          </Select>
        </Field>
        <div>
          <Label>Prioritas</Label>
          <div className="grid grid-cols-3 gap-1.5" role="radiogroup" aria-label="Prioritas">
            {BUCKETS.map((b) => {
              const active = f.bucket === b.id;
              return (
                <button
                  key={b.id}
                  type="button"
                  role="radio"
                  aria-checked={active}
                  title={b.meaning}
                  onClick={() => set("bucket", b.id)}
                  className={cn(
                    "h-10 rounded-lg border text-xs font-semibold transition",
                    active ? "text-white" : "border-border bg-surface text-muted hover:bg-accent",
                  )}
                  style={active ? { background: b.color, borderColor: b.color } : undefined}
                >
                  {b.emoji} {b.label}
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <Field label="Tanggal">
          <Input type="date" value={f.dueDate} onChange={(e) => set("dueDate", e.target.value)} />
        </Field>
        <Field label="Jam">
          <Input
            type="time"
            value={f.dueTime}
            onChange={(e) => set("dueTime", e.target.value)}
            disabled={!f.dueDate}
          />
        </Field>
      </div>

      {f.dueDate && f.dueTime && (
        <Field label="Pengingat (aplikasi HP)">
          <Select value={f.remind} onChange={(e) => set("remind", e.target.value)}>
            <option value="">Tanpa pengingat</option>
            {[...new Set([...REMIND_BEFORE_OPTIONS, ...(f.remind ? [Number(f.remind)] : [])])]
              .sort((a, b) => a - b)
              .map((m) => (
                <option key={m} value={m}>
                  {remindLabel(m)}
                </option>
              ))}
          </Select>
        </Field>
      )}

      {/* Recurrence builder */}
      <fieldset className="space-y-3 rounded-xl border border-border p-3">
        <legend className="px-1 text-sm font-medium text-foreground">Pengulangan</legend>
        <div className="grid grid-cols-4 gap-1.5">
          {(
            [
              ["", "Tidak"],
              ["daily", "Harian"],
              ["weekly", "Mingguan"],
              ["monthly", "Bulanan"],
            ] as const
          ).map(([v, label]) => (
            <button
              key={v}
              type="button"
              aria-pressed={f.freq === v}
              onClick={() => set("freq", v)}
              className={cn(
                "h-9 rounded-lg border text-xs font-medium transition",
                f.freq === v ? "border-primary bg-primary-soft text-primary" : "border-border bg-surface text-muted hover:bg-accent",
              )}
            >
              {label}
            </button>
          ))}
        </div>

        {f.freq && (
          <>
            <div className="flex items-center gap-2 text-sm text-foreground">
              <span>Setiap</span>
              <Input
                type="number"
                min={1}
                max={365}
                value={f.interval}
                onChange={(e) => set("interval", e.target.value)}
                className="h-9 w-20"
                aria-label="Interval"
              />
              <span>{f.freq === "daily" ? "hari" : f.freq === "weekly" ? "minggu" : "bulan"}</span>
            </div>

            {f.freq === "weekly" && (
              <div className="flex flex-wrap gap-1.5" aria-label="Hari">
                {WEEKDAYS_SHORT.map((d, i) => {
                  const wd = i + 1;
                  const implicit = f.weekdays.length === 0 && f.dueDate && isoWeekday(f.dueDate) === wd;
                  const on = f.weekdays.includes(wd) || !!implicit;
                  return (
                    <button
                      key={d}
                      type="button"
                      aria-pressed={on}
                      aria-label={WEEKDAYS_LONG[i]}
                      onClick={() => {
                        const base = f.weekdays.length === 0 && f.dueDate ? [isoWeekday(f.dueDate)] : f.weekdays;
                        set("weekdays", base.includes(wd) ? base.filter((x) => x !== wd) : [...base, wd].sort((a, b) => a - b));
                      }}
                      className={cn(
                        "h-9 w-11 rounded-lg border text-xs font-medium transition",
                        on ? "border-primary bg-primary text-white" : "border-border bg-surface text-muted hover:bg-accent",
                      )}
                    >
                      {d}
                    </button>
                  );
                })}
              </div>
            )}

            {f.freq === "monthly" && (
              <div className="flex items-center gap-2 text-sm text-foreground">
                <span>Tanggal</span>
                <Input
                  type="number"
                  min={1}
                  max={31}
                  value={f.monthDay}
                  placeholder={f.dueDate ? String(Number(f.dueDate.slice(8, 10))) : "1–31"}
                  onChange={(e) => set("monthDay", e.target.value)}
                  className="h-9 w-20"
                  aria-label="Tanggal setiap bulan"
                />
                <span className="text-xs text-muted">(disesuaikan ke akhir bulan jika lebih)</span>
              </div>
            )}

            <p className="text-xs text-muted">
              {!f.dueDate
                ? "Isi tanggal untuk tugas berulang — kejadian berikutnya dihitung dari tanggal itu."
                : previewRule && `${recurrenceLabel(previewRule)}. Menyelesaikan tugas ini membuat kejadian berikutnya.`}
            </p>
          </>
        )}
      </fieldset>

      {/* Money link */}
      <fieldset className="space-y-3 rounded-xl border border-border p-3">
        <legend className="px-1 text-sm font-medium text-foreground">Uang</legend>
        <label className="flex cursor-pointer items-center gap-2 text-sm text-foreground">
          <input
            type="checkbox"
            checked={f.money}
            onChange={(e) => set("money", e.target.checked)}
            className="h-4 w-4 accent-[var(--color-primary)]"
          />
          Tugas ini ada pengeluarannya (mis. bayar tagihan)
        </label>
        {f.money && (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <Field label="Nominal">
              <Input
                type="number"
                inputMode="decimal"
                min="0"
                step="any"
                value={f.amount}
                onChange={(e) => set("amount", e.target.value)}
                placeholder="0"
              />
            </Field>
            <Field label="Dompet">
              <Select value={f.walletId} onChange={(e) => set("walletId", e.target.value)}>
                <option value="">Pilih nanti</option>
                {wallets.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Kategori">
              <Select value={f.categoryId} onChange={(e) => set("categoryId", e.target.value)}>
                <option value="">Tanpa kategori</option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
            </Field>
          </div>
        )}
        {target.mode === "edit" && target.task.transactionId && (
          <p className="text-xs text-income">
            Pengeluaran {target.task.amount != null ? formatCurrency(target.task.amount, currency) : ""} sudah tercatat
            untuk tugas ini.
          </p>
        )}
      </fieldset>

      {error && <p className="text-sm text-expense">{error}</p>}

      <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
        {target.mode === "edit" ? (
          <Button type="button" variant="ghost" className="text-expense hover:text-expense" onClick={() => setConfirmDelete(true)} disabled={pending}>
            <Trash2 className="h-4 w-4" /> Hapus
          </Button>
        ) : (
          <span />
        )}
        <div className="flex gap-2">
          <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
            Batal
          </Button>
          <Button type="submit" loading={pending}>
            {pending ? "Menyimpan…" : target.mode === "edit" ? "Simpan" : "Tambah tugas"}
          </Button>
        </div>
      </div>
    </form>
  );
}
