"use client";

import * as React from "react";
import { AlertTriangle, Bell, Check, Pencil, Plus, Repeat, RotateCcw, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Field, Input, Select, Textarea } from "@/components/ui/input";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { RECURRENCE_LABELS, type ReminderStatus } from "@/lib/reminders";
import { REMINDER_NOTES_MAX, REMINDER_RECURRENCES, REMINDER_TITLE_MAX, type ReminderRecurrence } from "@/lib/schemas";
import { cn } from "@/lib/utils";
import { formatDateTime, fromLocalInput, toLocalInput, useTimeZone } from "../content/ui";
import {
  completeReminder,
  createReminder,
  deleteReminder,
  reopenReminder,
  updateReminder,
  type ReminderInput,
} from "./actions";

export type ReminderDTO = {
  id: string;
  title: string;
  notes: string | null;
  dueAt: string;
  recurrence: string | null;
  done: boolean;
  doneAt: string | null;
  /** Computed by the server at render time. */
  status: ReminderStatus;
};

const recurrenceLabel = (r: string | null) =>
  RECURRENCE_LABELS[(r && r in RECURRENCE_LABELS ? r : "none") as ReminderRecurrence | "none"];

export function ReminderBoard({ reminders }: { reminders: ReminderDTO[] }) {
  const [editing, setEditing] = React.useState<ReminderDTO | "new" | null>(null);
  const [deleting, setDeleting] = React.useState<ReminderDTO | null>(null);
  const [showDone, setShowDone] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const overdue = reminders.filter((r) => r.status === "overdue");
  const upcoming = reminders.filter((r) => r.status === "upcoming");
  const done = reminders.filter((r) => r.status === "done");

  const addButton = (
    <Button onClick={() => setEditing("new")}>
      <Plus className="h-4 w-4" />
      Tambah pengingat
    </Button>
  );

  return (
    <div>
      <PageHeader title="Pengingat" description="Hal yang perlu diingat, sekali atau berulang." action={addButton} />

      {error && (
        <div role="alert" className="mb-4 flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {overdue.length + upcoming.length === 0 && done.length === 0 ? (
        <EmptyState
          icon={Bell}
          title="Belum ada pengingat"
          description="Buat pengingat untuk tagihan, janji, atau hal kecil yang mudah terlupa."
          action={addButton}
        />
      ) : (
        <div className="space-y-6">
          {overdue.length > 0 && (
            <Section title="Terlambat" count={overdue.length} tone="overdue">
              {overdue.map((r) => (
                <ReminderRow key={r.id} r={r} onEdit={setEditing} onDelete={setDeleting} onError={setError} />
              ))}
            </Section>
          )}
          <Section title="Mendatang" count={upcoming.length}>
            {upcoming.length === 0 ? (
              <p className="px-4 py-6 text-center text-sm text-muted">Tidak ada pengingat mendatang.</p>
            ) : (
              upcoming.map((r) => (
                <ReminderRow key={r.id} r={r} onEdit={setEditing} onDelete={setDeleting} onError={setError} />
              ))
            )}
          </Section>
          {done.length > 0 && (
            <div>
              <button
                type="button"
                onClick={() => setShowDone((v) => !v)}
                className="mb-2 text-sm font-semibold text-muted hover:text-foreground"
                aria-expanded={showDone}
              >
                {showDone ? "Sembunyikan" : "Tampilkan"} yang selesai ({done.length})
              </button>
              {showDone && (
                <Card className="divide-y divide-border-soft overflow-hidden">
                  {done.map((r) => (
                    <ReminderRow key={r.id} r={r} onEdit={setEditing} onDelete={setDeleting} onError={setError} />
                  ))}
                </Card>
              )}
            </div>
          )}
        </div>
      )}

      <Modal
        open={editing !== null}
        onClose={() => setEditing(null)}
        title={editing === "new" ? "Pengingat baru" : "Ubah pengingat"}
      >
        {editing !== null && (
          <ReminderForm reminder={editing === "new" ? null : editing} onClose={() => setEditing(null)} />
        )}
      </Modal>

      {deleting && <DeleteDialog reminder={deleting} onClose={() => setDeleting(null)} />}
    </div>
  );
}

function Section({
  title,
  count,
  tone,
  children,
}: {
  title: string;
  count: number;
  tone?: "overdue";
  children: React.ReactNode;
}) {
  return (
    <section>
      <h2 className={cn("mb-2 text-sm font-semibold", tone === "overdue" ? "text-expense" : "text-foreground")}>
        {title} <span className="font-normal text-muted">({count})</span>
      </h2>
      <Card className="divide-y divide-border-soft overflow-hidden">{children}</Card>
    </section>
  );
}

function ReminderRow({
  r,
  onEdit,
  onDelete,
  onError,
}: {
  r: ReminderDTO;
  onEdit: (r: ReminderDTO) => void;
  onDelete: (r: ReminderDTO) => void;
  onError: (e: string | null) => void;
}) {
  const tz = useTimeZone();
  const [pending, startTransition] = React.useTransition();

  function toggle() {
    onError(null);
    startTransition(async () => {
      const res = r.done ? await reopenReminder(r.id) : await completeReminder(r.id, tz);
      if (!res.ok) onError(res.error);
    });
  }

  return (
    <div className={cn("flex items-start gap-3 px-4 py-3", pending && "opacity-60")}>
      <button
        type="button"
        onClick={toggle}
        disabled={pending}
        aria-label={r.done ? "Tandai belum selesai" : "Tandai selesai"}
        className={cn(
          "mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2 transition",
          r.done
            ? "border-income bg-income text-white"
            : r.status === "overdue"
              ? "border-expense text-transparent hover:text-expense"
              : "border-border text-transparent hover:border-primary hover:text-primary",
        )}
      >
        <Check className="h-3.5 w-3.5" />
      </button>
      <div className="min-w-0 flex-1">
        <p className={cn("break-words text-sm font-medium", r.done ? "text-muted line-through" : "text-foreground")}>
          {r.title}
        </p>
        <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted">
          <span className={cn(r.status === "overdue" && "font-medium text-expense")}>
            {formatDateTime(r.dueAt, tz, { year: true })}
          </span>
          {r.recurrence && (
            <span className="inline-flex items-center gap-1">
              <Repeat className="h-3 w-3" />
              {recurrenceLabel(r.recurrence)}
            </span>
          )}
          {r.done && r.doneAt && <span>· selesai {formatDateTime(r.doneAt, tz, { weekday: false })}</span>}
        </div>
        {r.notes && <p className="mt-1 whitespace-pre-wrap break-words text-xs text-muted-soft">{r.notes}</p>}
      </div>
      <div className="flex shrink-0 items-center gap-0.5">
        {r.done ? (
          <Button variant="ghost" size="icon" onClick={toggle} aria-label="Buka lagi" disabled={pending}>
            <RotateCcw className="h-4 w-4" />
          </Button>
        ) : (
          <Button variant="ghost" size="icon" onClick={() => onEdit(r)} aria-label="Ubah">
            <Pencil className="h-4 w-4" />
          </Button>
        )}
        <Button variant="ghost" size="icon" onClick={() => onDelete(r)} aria-label="Hapus">
          <Trash2 className="h-4 w-4 text-expense" />
        </Button>
      </div>
    </div>
  );
}

/** Default due time for a new reminder: the next full hour. */
function nextHourIso() {
  const d = new Date();
  d.setMinutes(0, 0, 0);
  d.setHours(d.getHours() + 1);
  return d.toISOString();
}

function ReminderForm({ reminder, onClose }: { reminder: ReminderDTO | null; onClose: () => void }) {
  const [error, setError] = React.useState<string | null>(null);
  const [pending, startTransition] = React.useTransition();

  function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const dueAt = fromLocalInput(String(fd.get("dueAt") ?? ""));
    if (!dueAt) {
      setError("Waktu tidak valid");
      return;
    }
    const input: ReminderInput = {
      title: String(fd.get("title") ?? ""),
      notes: String(fd.get("notes") ?? ""),
      dueAt,
      recurrence: String(fd.get("recurrence") ?? "none") as ReminderInput["recurrence"],
    };
    setError(null);
    startTransition(async () => {
      const res = reminder ? await updateReminder(reminder.id, input) : await createReminder(input);
      if (res.ok) onClose();
      else setError(res.error);
    });
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <Field label="Judul">
        <Input name="title" required maxLength={REMINDER_TITLE_MAX} autoFocus defaultValue={reminder?.title ?? ""} placeholder="mis. Bayar listrik" />
      </Field>
      <Field label="Waktu">
        <Input name="dueAt" type="datetime-local" required defaultValue={toLocalInput(reminder?.dueAt ?? nextHourIso())} />
      </Field>
      <Field label="Ulangi">
        <Select name="recurrence" defaultValue={reminder?.recurrence ?? "none"}>
          {(["none", ...REMINDER_RECURRENCES] as const).map((r) => (
            <option key={r} value={r}>
              {RECURRENCE_LABELS[r]}
            </option>
          ))}
        </Select>
      </Field>
      <Field label="Catatan">
        <Textarea name="notes" maxLength={REMINDER_NOTES_MAX} defaultValue={reminder?.notes ?? ""} placeholder="Opsional" />
      </Field>
      {error && <p className="text-sm text-expense">{error}</p>}
      <div className="flex justify-end gap-2 pt-1">
        <Button type="button" variant="outline" onClick={onClose} disabled={pending}>
          Batal
        </Button>
        <Button type="submit" loading={pending}>
          {pending ? "Menyimpan…" : "Simpan"}
        </Button>
      </div>
    </form>
  );
}

function DeleteDialog({ reminder, onClose }: { reminder: ReminderDTO; onClose: () => void }) {
  const [pending, startTransition] = React.useTransition();
  const [error, setError] = React.useState<string | null>(null);
  function run() {
    startTransition(async () => {
      const res = await deleteReminder(reminder.id);
      if (res.ok) onClose();
      else setError(res.error);
    });
  }
  return (
    <Modal open onClose={onClose} title="Hapus pengingat?" description={`"${reminder.title}" akan dihapus permanen.`}>
      {error && <p className="mb-3 text-sm text-expense">{error}</p>}
      <div className="flex justify-end gap-2">
        <Button variant="outline" onClick={onClose} disabled={pending}>
          Batal
        </Button>
        <Button variant="danger" onClick={run} loading={pending}>
          {pending ? "Menghapus…" : "Hapus"}
        </Button>
      </div>
    </Modal>
  );
}
