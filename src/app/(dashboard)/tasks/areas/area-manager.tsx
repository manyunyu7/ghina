"use client";

import * as React from "react";
import Link from "next/link";
import { AlertTriangle, Archive, ArchiveRestore, ArrowDown, ArrowLeft, ArrowUp, Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Field, Input, Label } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { CategoryIcon } from "@/components/icon";
import { CATEGORY_ICONS, COLOR_PALETTE } from "@/lib/constants";
import { AREA_CODE_MAX, AREA_NAME_MAX, BUCKETS, DEFAULT_AREA_COLOR, DEFAULT_AREA_ICON, type AreaSchedule } from "@/lib/tasks";
import { cn } from "@/lib/utils";
import {
  createTaskArea,
  deleteTaskArea,
  reorderTaskAreas,
  updateTaskArea,
  type TaskActionResult,
  type TaskAreaInput,
} from "../actions";
import { WEEKDAYS_LONG, WEEKDAYS_SHORT, errorText } from "../format";
import { scheduleLabel } from "../schedule";
import type { AreaDTO } from "../types";

const AREA_COLORS = [...new Set([...BUCKETS.map((b) => b.color), DEFAULT_AREA_COLOR, "#FF9600", "#FFC800", ...COLOR_PALETTE])];

export function AreaManager({ areas, taskCounts }: { areas: AreaDTO[]; taskCounts: Record<string, number> }) {
  const [list, apply] = React.useOptimistic(areas, (s: AreaDTO[], fn: (s: AreaDTO[]) => AreaDTO[]) => fn(s));
  const [, startTransition] = React.useTransition();
  const [error, setError] = React.useState<string | null>(null);
  const [editing, setEditing] = React.useState<AreaDTO | "new" | null>(null);
  const [deleting, setDeleting] = React.useState<AreaDTO | null>(null);

  const active = list.filter((a) => !a.archived);
  const archived = list.filter((a) => a.archived);

  function mutate(fn: (s: AreaDTO[]) => AreaDTO[], action: () => Promise<TaskActionResult>) {
    setError(null);
    startTransition(async () => {
      apply(fn);
      let res: TaskActionResult;
      try {
        res = await action();
      } catch {
        res = { ok: false, error: "Something went wrong" };
      }
      if (!res.ok) setError(errorText(res.error));
    });
  }

  function move(area: AreaDTO, dir: -1 | 1) {
    const ids = active.map((a) => a.id);
    const i = ids.indexOf(area.id);
    const j = i + dir;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    const order = [...ids, ...archived.map((a) => a.id)];
    mutate(
      (s) => order.map((id, k) => ({ ...s.find((a) => a.id === id)!, sortOrder: k })),
      () => reorderTaskAreas(order),
    );
  }

  function setArchived(area: AreaDTO, value: boolean) {
    mutate((s) => s.map((a) => (a.id === area.id ? { ...a, archived: value } : a)), () => updateTaskArea(area.id, { archived: value }));
  }

  return (
    <div>
      <Link href="/tasks" className="mb-3 inline-flex items-center gap-1 text-sm font-medium text-muted hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Kembali ke Tugas
      </Link>
      <PageHeader
        title="Area tugas"
        description="Area adalah konteks hidupmu (Kerjaan, Keseharian, Kuliah…). Jadwal area menentukan mode Fokus."
        action={
          <Button onClick={() => setEditing("new")}>
            <Plus className="h-4 w-4" /> Area baru
          </Button>
        }
      />

      {error && <p className="mb-4 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">{error}</p>}

      <Card className="divide-y divide-border">
        {active.length === 0 && <p className="p-6 text-center text-sm text-muted">Belum ada area aktif.</p>}
        {active.map((a, i) => (
          <AreaRow
            key={a.id}
            area={a}
            count={taskCounts[a.id] ?? 0}
            onEdit={() => setEditing(a)}
            onDelete={() => setDeleting(a)}
            actions={
              <>
                <Button variant="ghost" size="icon" aria-label={`Naikkan ${a.name}`} disabled={i === 0} onClick={() => move(a, -1)}>
                  <ArrowUp className="h-4 w-4" />
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label={`Turunkan ${a.name}`}
                  disabled={i === active.length - 1}
                  onClick={() => move(a, 1)}
                >
                  <ArrowDown className="h-4 w-4" />
                </Button>
                <Button variant="ghost" size="icon" aria-label={`Arsipkan ${a.name}`} title="Arsipkan" onClick={() => setArchived(a, true)}>
                  <Archive className="h-4 w-4" />
                </Button>
              </>
            }
          />
        ))}
      </Card>

      {archived.length > 0 && (
        <>
          <h2 className="mb-2 mt-8 text-sm font-semibold text-muted">Diarsipkan</h2>
          <p className="mb-3 text-xs text-muted">Area yang diarsipkan disembunyikan dari papan dan mode Fokus; tugasnya tetap tersimpan.</p>
          <Card className="divide-y divide-border opacity-80">
            {archived.map((a) => (
              <AreaRow
                key={a.id}
                area={a}
                count={taskCounts[a.id] ?? 0}
                onEdit={() => setEditing(a)}
                onDelete={() => setDeleting(a)}
                actions={
                  <Button variant="ghost" size="icon" aria-label={`Aktifkan ${a.name}`} title="Aktifkan lagi" onClick={() => setArchived(a, false)}>
                    <ArchiveRestore className="h-4 w-4" />
                  </Button>
                }
              />
            ))}
          </Card>
        </>
      )}

      <Modal
        open={editing !== null}
        onClose={() => setEditing(null)}
        title={editing === "new" ? "Area baru" : "Edit area"}
        className="sm:max-w-lg"
      >
        {editing !== null && (
          <AreaForm key={editing === "new" ? "new" : editing.id} area={editing === "new" ? null : editing} onDone={() => setEditing(null)} />
        )}
      </Modal>

      <Modal open={!!deleting} onClose={() => setDeleting(null)} title="Hapus area">
        {deleting && (
          <div className="space-y-4">
            <div className="flex gap-3 rounded-lg bg-expense-soft p-3 text-expense">
              <AlertTriangle className="h-5 w-5 shrink-0" />
              <div className="text-sm">
                <p className="font-medium">Tidak bisa dibatalkan.</p>
                <p className="mt-0.5 text-expense/90">
                  Area <span className="font-semibold">{deleting.name}</span> dan{" "}
                  <span className="font-semibold">{taskCounts[deleting.id] ?? 0} tugasnya</span> (termasuk yang sudah selesai) akan
                  dihapus permanen di web dan HP. Pengeluaran yang sudah tercatat tetap ada. Mau menyimpan tugasnya? Arsipkan saja.
                </p>
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setDeleting(null)}>
                Batal
              </Button>
              <Button
                variant="danger"
                onClick={() => {
                  const a = deleting;
                  setDeleting(null);
                  mutate((s) => s.filter((x) => x.id !== a.id), () => deleteTaskArea(a.id));
                }}
              >
                Hapus area & tugas
              </Button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}

function AreaRow({
  area,
  count,
  actions,
  onEdit,
  onDelete,
}: {
  area: AreaDTO;
  count: number;
  actions: React.ReactNode;
  onEdit: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-3 p-4">
      <span
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full"
        style={{ background: `${area.color}1f`, color: area.color }}
      >
        <CategoryIcon name={area.icon} className="h-5 w-5" />
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate font-medium text-foreground">{area.name}</span>
          <span className="rounded px-1.5 text-[11px] font-bold tracking-wide" style={{ background: `${area.color}1f`, color: area.color }}>
            {area.code}
          </span>
        </div>
        <p className="mt-0.5 text-xs text-muted">
          {scheduleLabel(area.schedule)} · {count} tugas
        </p>
      </div>
      <div className="flex items-center gap-0.5">
        {actions}
        <Button variant="ghost" size="icon" aria-label={`Edit ${area.name}`} onClick={onEdit}>
          <Pencil className="h-4 w-4" />
        </Button>
        <Button variant="ghost" size="icon" aria-label={`Hapus ${area.name}`} onClick={onDelete} className="hover:text-expense">
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}

const suggestCode = (name: string) =>
  name
    .normalize("NFD")
    .replace(/[^A-Za-z0-9]/g, "")
    .toUpperCase()
    .slice(0, 5);

function AreaForm({ area, onDone }: { area: AreaDTO | null; onDone: () => void }) {
  const [name, setName] = React.useState(area?.name ?? "");
  const [code, setCode] = React.useState(area?.code ?? "");
  const [codeTouched, setCodeTouched] = React.useState(!!area);
  const [color, setColor] = React.useState(area?.color ?? DEFAULT_AREA_COLOR);
  const [icon, setIcon] = React.useState(area?.icon ?? DEFAULT_AREA_ICON);
  const [scheduled, setScheduled] = React.useState(!!area?.schedule);
  const [days, setDays] = React.useState<number[]>(area?.schedule?.days ?? [1, 2, 3, 4, 5]);
  const [start, setStart] = React.useState(area?.schedule?.start ?? "09:00");
  const [end, setEnd] = React.useState(area?.schedule?.end ?? "17:00");
  const [error, setError] = React.useState<string | null>(null);
  const [pending, setPending] = React.useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return setError("Nama wajib diisi");
    if (!/^[A-Z0-9]{1,8}$/.test(code)) return setError("Kode harus 1–8 huruf/angka (A–Z, 0–9)");
    let schedule: AreaSchedule | null = null;
    if (scheduled) {
      if (days.length === 0) return setError("Pilih minimal satu hari");
      if (!start || !end || start >= end) return setError("Jam mulai harus sebelum jam selesai (tidak bisa lewat tengah malam)");
      schedule = { days, start, end };
    }
    const input: TaskAreaInput = { name: name.trim(), code, color, icon, schedule };
    setPending(true);
    setError(null);
    try {
      const res = area ? await updateTaskArea(area.id, input) : await createTaskArea(input);
      if (res.ok) onDone();
      else setError(errorText(res.error));
    } catch {
      setError("Terjadi kesalahan");
    } finally {
      setPending(false);
    }
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="grid grid-cols-[1fr_7.5rem] gap-3">
        <Field label="Nama">
          <Input
            value={name}
            maxLength={AREA_NAME_MAX}
            onChange={(e) => {
              setName(e.target.value);
              if (!codeTouched) setCode(suggestCode(e.target.value));
            }}
            placeholder="Contoh: Kuliah"
            autoFocus
            required
          />
        </Field>
        <Field label="Kode">
          <Input
            value={code}
            maxLength={AREA_CODE_MAX}
            onChange={(e) => {
              setCodeTouched(true);
              setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, AREA_CODE_MAX));
            }}
            placeholder="KULIAH"
            className="font-mono uppercase tracking-wider"
            aria-describedby="code-hint"
            required
          />
        </Field>
      </div>
      <p id="code-hint" className="-mt-2 text-xs text-muted">
        Kode dipakai di notifikasi HP, mis. <span className="font-mono">[{code || "KODE"}-FIRE] Judul tugas</span>.
      </p>

      <div>
        <Label>Warna</Label>
        <div className="flex flex-wrap gap-2">
          {AREA_COLORS.map((c) => (
            <button
              key={c}
              type="button"
              aria-label={`Warna ${c}`}
              aria-pressed={color.toLowerCase() === c.toLowerCase()}
              onClick={() => setColor(c)}
              className={cn(
                "h-7 w-7 rounded-full transition",
                color.toLowerCase() === c.toLowerCase() && "ring-2 ring-foreground ring-offset-2 ring-offset-card",
              )}
              style={{ background: c }}
            />
          ))}
        </div>
      </div>

      <div>
        <Label>Ikon</Label>
        <div className="grid grid-cols-8 gap-1.5 sm:grid-cols-10">
          {CATEGORY_ICONS.map((ic) => (
            <button
              key={ic}
              type="button"
              aria-label={`Ikon ${ic}`}
              aria-pressed={icon === ic}
              onClick={() => setIcon(ic)}
              className={cn(
                "flex aspect-square items-center justify-center rounded-lg border transition",
                icon === ic ? "border-transparent text-white" : "border-border text-muted hover:bg-accent",
              )}
              style={icon === ic ? { background: color } : undefined}
            >
              <CategoryIcon name={ic} className="h-4 w-4" />
            </button>
          ))}
        </div>
      </div>

      <fieldset className="space-y-3 rounded-xl border border-border p-3">
        <legend className="px-1 text-sm font-medium text-foreground">Jadwal aktif</legend>
        <div className="grid grid-cols-2 gap-1.5">
          {[
            [false, "Tanpa jadwal"],
            [true, "Terjadwal"],
          ].map(([v, label]) => (
            <button
              key={String(v)}
              type="button"
              aria-pressed={scheduled === v}
              onClick={() => setScheduled(v as boolean)}
              className={cn(
                "h-9 rounded-lg border text-sm font-medium transition",
                scheduled === v ? "border-primary bg-primary-soft text-primary" : "border-border bg-surface text-muted hover:bg-accent",
              )}
            >
              {label as string}
            </button>
          ))}
        </div>
        {scheduled ? (
          <>
            <div className="flex flex-wrap gap-1.5">
              {WEEKDAYS_SHORT.map((d, i) => {
                const wd = i + 1;
                const on = days.includes(wd);
                return (
                  <button
                    key={d}
                    type="button"
                    aria-pressed={on}
                    aria-label={WEEKDAYS_LONG[i]}
                    onClick={() => setDays(on ? days.filter((x) => x !== wd) : [...days, wd].sort((a, b) => a - b))}
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
            <div className="grid grid-cols-2 gap-3">
              <Field label="Mulai">
                <Input type="time" value={start} onChange={(e) => setStart(e.target.value)} />
              </Field>
              <Field label="Selesai">
                <Input type="time" value={end} onChange={(e) => setEnd(e.target.value)} />
              </Field>
            </div>
            <p className="text-xs text-muted">Selama jam ini, mode Fokus menampilkan area ini.</p>
          </>
        ) : (
          <p className="text-xs text-muted">Area tanpa jadwal jadi fokus saat tidak ada area terjadwal yang sedang aktif.</p>
        )}
      </fieldset>

      {error && <p className="text-sm text-expense">{error}</p>}

      <div className="flex justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onDone} disabled={pending}>
          Batal
        </Button>
        <Button type="submit" disabled={pending}>
          {pending ? "Menyimpan…" : area ? "Simpan" : "Buat area"}
        </Button>
      </div>
    </form>
  );
}
