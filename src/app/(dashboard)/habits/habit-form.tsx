"use client";

import * as React from "react";
import { Archive, ArchiveRestore, Lock, Plus, Trash2, X } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Label, Textarea } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import {
  DEFAULT_COUNT_UNIT,
  DEFAULT_HABIT_COLOR,
  HABIT_NAME_MAX,
  HABIT_REMINDERS_MAX,
  HABIT_UNIT_MAX,
  HABIT_WHY_MAX,
  type HabitKind,
  type HabitSchedule,
  type HabitTarget,
} from "@/lib/habits";
import type { HabitDTO } from "@/lib/habits-server";
import { createHabit, deleteHabit, setHabitArchived, updateHabit, type HabitInput } from "./actions";
import { ErrorLine } from "./parts";
import { WEEKDAYS_SHORT } from "./format";

const EMOJIS = [
  "💪", "🏃", "🚶", "🧘", "🏋️", "🚴", "🏊", "⚽", "📖", "📚", "✍️", "🧠",
  "💧", "🥗", "🍎", "🥦", "😴", "🌅", "🙏", "🕌", "📿", "🎸", "🎨", "💻",
  "🧹", "🪴", "💰", "📵", "🚭", "🍺", "🎰", "🍬", "☕", "🎮", "📱", "🌙",
  "🔥", "🌱", "⭐", "❤️",
];

const COLORS = ["#58CC02", "#1CB0F6", "#CE82FF", "#FF9600", "#FF4B4B", "#FFC800", "#2B70C9", "#00CD9C", "#FF86D0", "#64748B"];

type Form = {
  name: string;
  emoji: string;
  color: string;
  kind: HabitKind;
  scheduleType: HabitSchedule["type"];
  days: number[];
  times: number;
  targetType: HabitTarget["type"];
  goal: string;
  unit: string;
  reminders: string[];
  private: boolean;
  why: string;
  startDate: string;
};

function initialForm(habit: HabitDTO | null, today: string, kind: HabitKind): Form {
  if (!habit)
    return {
      name: "",
      emoji: kind === "quit" ? "🚭" : "💪",
      color: kind === "quit" ? "#1CB0F6" : DEFAULT_HABIT_COLOR,
      kind,
      scheduleType: "daily",
      days: [1, 2, 3, 4, 5],
      times: 3,
      targetType: "check",
      goal: "",
      unit: "",
      reminders: [],
      private: false,
      why: "",
      startDate: today,
    };
  const s = habit.schedule;
  const t = habit.target;
  return {
    name: habit.name,
    emoji: habit.emoji ?? "",
    color: habit.color,
    kind: habit.kind === "quit" ? "quit" : "build",
    scheduleType: s.type,
    days: s.type === "weekdays" ? s.days : [1, 2, 3, 4, 5],
    times: s.type === "perWeek" ? s.times : 3,
    targetType: t.type,
    goal: t.type === "check" ? "" : String(t.goal),
    unit: t.type === "count" ? t.unit : "",
    reminders: habit.reminders,
    private: habit.private,
    why: habit.why ?? "",
    startDate: habit.startDate,
  };
}

function toInput(f: Form): { input: HabitInput } | { error: string } {
  if (!f.name.trim()) return { error: "Nama wajib diisi" };
  let schedule: HabitSchedule = { type: "daily" };
  let target: HabitTarget = { type: "check" };
  if (f.kind === "build") {
    if (f.scheduleType === "weekdays") {
      if (!f.days.length) return { error: "Pilih minimal satu hari" };
      schedule = { type: "weekdays", days: f.days };
    } else if (f.scheduleType === "perWeek") schedule = { type: "perWeek", times: f.times };
    if (f.targetType !== "check") {
      const goal = Number(f.goal.replace(",", "."));
      if (!f.goal.trim() || !Number.isFinite(goal) || goal <= 0) return { error: "Isi target harian (lebih dari 0)" };
      target =
        f.targetType === "count"
          ? { type: "count", goal, unit: f.unit.trim() || DEFAULT_COUNT_UNIT }
          : { type: "duration", goal: Math.round(goal) };
    }
  }
  return {
    input: {
      name: f.name,
      emoji: f.emoji || null,
      color: f.color,
      kind: f.kind,
      schedule,
      target,
      reminders: f.reminders.filter(Boolean),
      private: f.private,
      why: f.why.trim() || null,
      startDate: f.startDate,
    },
  };
}

export type HabitFormTarget = { mode: "create"; kind: HabitKind } | { mode: "edit"; habit: HabitDTO };

/** Create / edit a habit (plus archive and delete when editing). */
export function HabitFormDialog({
  target,
  today,
  onClose,
  onCreated,
  onDeleted,
}: {
  target: HabitFormTarget | null;
  today: string;
  onClose: () => void;
  onCreated?: (id: string) => void;
  onDeleted?: () => void;
}) {
  return (
    <Modal
      open={!!target}
      onClose={onClose}
      title={target?.mode === "edit" ? "Ubah kebiasaan" : "Kebiasaan baru"}
      className="sm:max-w-xl"
    >
      {target && (
        <HabitForm
          key={target.mode === "edit" ? target.habit.id : `new-${target.kind}`}
          target={target}
          today={today}
          onClose={onClose}
          onCreated={onCreated}
          onDeleted={onDeleted}
        />
      )}
    </Modal>
  );
}

function HabitForm({
  target,
  today,
  onClose,
  onCreated,
  onDeleted,
}: {
  target: HabitFormTarget;
  today: string;
  onClose: () => void;
  onCreated?: (id: string) => void;
  onDeleted?: () => void;
}) {
  const habit = target.mode === "edit" ? target.habit : null;
  const [f, setF] = React.useState<Form>(() => initialForm(habit, today, target.mode === "create" ? target.kind : "build"));
  const [error, setError] = React.useState<string | null>(null);
  const [pending, startTransition] = React.useTransition();
  const [busy, setBusy] = React.useState<"save" | "archive" | "delete" | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const [newReminder, setNewReminder] = React.useState("07:00");
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setF((p) => ({ ...p, [k]: v }));
  const quit = f.kind === "quit";

  function run(kind: "save" | "archive" | "delete", fn: () => Promise<{ ok: boolean; error?: string; id?: string }>) {
    setError(null);
    setBusy(kind);
    startTransition(async () => {
      try {
        const res = await fn();
        if (res.ok) {
          if (kind === "delete") onDeleted?.();
          else if (kind === "save" && res.id) onCreated?.(res.id);
          onClose();
        } else setError(res.error ?? "Terjadi kesalahan");
      } catch {
        setError("Gagal menyimpan, periksa koneksi");
      }
    });
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const built = toInput(f);
    if ("error" in built) {
      setError(built.error);
      return;
    }
    run("save", () => (habit ? updateHabit(habit.id, built.input) : createHabit(built.input)));
  }

  const addReminder = () => {
    if (!newReminder || f.reminders.includes(newReminder) || f.reminders.length >= HABIT_REMINDERS_MAX) return;
    set("reminders", [...f.reminders, newReminder].sort());
  };

  return (
    <form onSubmit={submit} className="space-y-5">
      {/* Kind */}
      <div className="grid grid-cols-2 gap-2" role="radiogroup" aria-label="Jenis kebiasaan">
        {(
          [
            ["build", "🌱 Membangun", "Mulai kebiasaan baik"],
            ["quit", "🛡️ Berhenti", "Lepas dari kebiasaan buruk"],
          ] as const
        ).map(([k, label, hint]) => (
          <button
            key={k}
            type="button"
            role="radio"
            aria-checked={f.kind === k}
            onClick={() => set("kind", k)}
            className={cn(
              "rounded-xl border-2 p-3 text-left transition",
              f.kind === k ? "border-primary bg-primary-soft" : "border-border hover:bg-accent",
            )}
          >
            <span className="block text-sm font-semibold text-foreground">{label}</span>
            <span className="block text-xs text-muted">{hint}</span>
          </button>
        ))}
      </div>
      {habit && habit.kind !== f.kind && (
        <p className="-mt-3 text-xs text-muted">Riwayat lama tetap disimpan; catatan jenis lain diabaikan dalam hitungan streak.</p>
      )}

      {/* Name + emoji */}
      <div>
        <Label htmlFor="habit-name">Nama</Label>
        <div className="flex gap-2">
          <span
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-xl"
            style={{ background: `${f.color}22` }}
            aria-hidden
          >
            {f.emoji || "•"}
          </span>
          <Input
            id="habit-name"
            value={f.name}
            maxLength={HABIT_NAME_MAX}
            onChange={(e) => set("name", e.target.value)}
            placeholder={quit ? "mis. Berhenti merokok" : "mis. Baca buku 10 halaman"}
            required
            autoFocus={!habit}
          />
        </div>
      </div>

      <div>
        <Label>Emoji</Label>
        <div className="grid grid-cols-8 gap-1 sm:grid-cols-10">
          {EMOJIS.map((e) => (
            <button
              key={e}
              type="button"
              onClick={() => set("emoji", f.emoji === e ? "" : e)}
              aria-label={`Emoji ${e}`}
              aria-pressed={f.emoji === e}
              className={cn(
                "flex h-9 items-center justify-center rounded-lg text-lg transition hover:bg-accent",
                f.emoji === e && "bg-primary-soft ring-2 ring-primary",
              )}
            >
              {e}
            </button>
          ))}
        </div>
        <div className="mt-2 flex items-center gap-2">
          <Input
            value={EMOJIS.includes(f.emoji) ? "" : f.emoji}
            onChange={(e) => set("emoji", [...e.target.value.trim()].slice(0, 2).join(""))}
            placeholder="Emoji lain…"
            aria-label="Emoji lain"
            className="h-9 w-32"
          />
          {f.emoji && (
            <button type="button" className="text-xs font-medium text-muted hover:underline" onClick={() => set("emoji", "")}>
              Tanpa emoji
            </button>
          )}
        </div>
      </div>

      <div>
        <Label>Warna</Label>
        <div className="flex flex-wrap gap-2">
          {COLORS.map((c) => (
            <button
              key={c}
              type="button"
              onClick={() => set("color", c)}
              aria-label={`Warna ${c}`}
              aria-pressed={f.color === c}
              className={cn("h-8 w-8 rounded-full transition", f.color === c && "ring-2 ring-offset-2")}
              style={{ background: c, ["--tw-ring-color" as string]: c }}
            />
          ))}
        </div>
      </div>

      {/* Schedule + target (build only) */}
      {quit ? (
        <p className="rounded-xl bg-accent/70 p-3 text-xs text-muted">
          Kebiasaan berhenti selalu dihitung per hari: setiap hari tanpa kambuh = satu hari bersih.
        </p>
      ) : (
        <>
          <div>
            <Label>Jadwal</Label>
            <div className="flex flex-wrap gap-2">
              {(
                [
                  ["daily", "Setiap hari"],
                  ["weekdays", "Hari tertentu"],
                  ["perWeek", "N× per minggu"],
                ] as const
              ).map(([k, label]) => (
                <SegButton key={k} active={f.scheduleType === k} onClick={() => set("scheduleType", k)}>
                  {label}
                </SegButton>
              ))}
            </div>
            {f.scheduleType === "weekdays" && (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {WEEKDAYS_SHORT.map((d, i) => {
                  const day = i + 1;
                  const on = f.days.includes(day);
                  return (
                    <button
                      key={d}
                      type="button"
                      aria-pressed={on}
                      onClick={() => set("days", on ? f.days.filter((x) => x !== day) : [...f.days, day].sort())}
                      className={cn(
                        "h-9 w-11 rounded-lg border text-sm font-medium transition",
                        on ? "border-transparent bg-primary text-white" : "border-border bg-surface hover:bg-accent",
                      )}
                    >
                      {d}
                    </button>
                  );
                })}
              </div>
            )}
            {f.scheduleType === "perWeek" && (
              <div className="mt-2 flex flex-wrap items-center gap-1.5">
                {[1, 2, 3, 4, 5, 6, 7].map((n) => (
                  <button
                    key={n}
                    type="button"
                    aria-pressed={f.times === n}
                    onClick={() => set("times", n)}
                    className={cn(
                      "h-9 w-9 rounded-lg border text-sm font-medium transition",
                      f.times === n ? "border-transparent bg-primary text-white" : "border-border bg-surface hover:bg-accent",
                    )}
                  >
                    {n}
                  </button>
                ))}
                <span className="text-sm text-muted">kali per minggu (Sen–Min)</span>
              </div>
            )}
          </div>

          <div>
            <Label>Target harian</Label>
            <div className="flex flex-wrap gap-2">
              {(
                [
                  ["check", "✓ Centang"],
                  ["count", "# Jumlah"],
                  ["duration", "⏱ Durasi"],
                ] as const
              ).map(([k, label]) => (
                <SegButton key={k} active={f.targetType === k} onClick={() => set("targetType", k)}>
                  {label}
                </SegButton>
              ))}
            </div>
            {f.targetType !== "check" && (
              <div className="mt-2 flex items-center gap-2">
                <Input
                  type="number"
                  inputMode="decimal"
                  min={f.targetType === "duration" ? 1 : 0}
                  step={f.targetType === "duration" ? 1 : "any"}
                  value={f.goal}
                  onChange={(e) => set("goal", e.target.value)}
                  placeholder={f.targetType === "duration" ? "30" : "8"}
                  aria-label="Target"
                  className="w-28"
                />
                {f.targetType === "count" ? (
                  <Input
                    value={f.unit}
                    maxLength={HABIT_UNIT_MAX}
                    onChange={(e) => set("unit", e.target.value)}
                    placeholder="satuan: gelas, halaman…"
                    aria-label="Satuan"
                  />
                ) : (
                  <span className="text-sm text-muted">menit per hari</span>
                )}
              </div>
            )}
          </div>
        </>
      )}

      {/* Start date */}
      <div>
        <Label htmlFor="habit-start">{quit ? "Sudah bersih sejak…" : "Mulai tanggal"}</Label>
        <Input
          id="habit-start"
          type="date"
          value={f.startDate}
          onChange={(e) => set("startDate", e.target.value || today)}
          className="w-48"
        />
        {quit && <p className="mt-1 text-xs text-muted">Hari bersih dihitung dari tanggal ini (hari ini ikut dihitung).</p>}
      </div>

      {/* Why */}
      <div>
        <Label htmlFor="habit-why">{quit ? "Alasan aku berhenti" : "Alasan aku mulai"}</Label>
        <Textarea
          id="habit-why"
          value={f.why}
          maxLength={HABIT_WHY_MAX}
          onChange={(e) => set("why", e.target.value)}
          placeholder={quit ? "Biar lebih sehat, biar uangnya bisa ditabung, demi keluarga…" : "Kenapa ini penting buatmu?"}
        />
        {quit && <p className="mt-1 text-xs text-muted">Ditampilkan saat kamu menekan tombol “Lagi pengen…”.</p>}
      </div>

      {/* Reminders */}
      <div>
        <Label>Pengingat</Label>
        <div className="flex flex-wrap items-center gap-2">
          {f.reminders.map((r) => (
            <span key={r} className="inline-flex h-8 items-center gap-1 rounded-full bg-accent pl-3 pr-1 text-sm font-medium tabular-nums">
              {r}
              <button
                type="button"
                aria-label={`Hapus pengingat ${r}`}
                onClick={() => set("reminders", f.reminders.filter((x) => x !== r))}
                className="rounded-full p-1 text-muted hover:bg-border-soft hover:text-foreground"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </span>
          ))}
          {f.reminders.length < HABIT_REMINDERS_MAX && (
            <span className="inline-flex items-center gap-1">
              <Input
                type="time"
                value={newReminder}
                onChange={(e) => setNewReminder(e.target.value)}
                aria-label="Jam pengingat"
                className="h-8 w-28"
              />
              <Button type="button" variant="outline" size="sm" onClick={addReminder}>
                <Plus className="h-4 w-4" /> Tambah
              </Button>
            </span>
          )}
        </div>
        <p className="mt-1 text-xs text-muted">
          Notifikasi pengingat dikirim oleh aplikasi Ghina di HP. Web hanya menyimpan dan menampilkan jadwalnya.
        </p>
      </div>

      {/* Private */}
      <label className="flex cursor-pointer items-start gap-3 rounded-xl border border-border p-3">
        <input
          type="checkbox"
          checked={f.private}
          onChange={(e) => set("private", e.target.checked)}
          className="mt-0.5 h-4 w-4 accent-[var(--color-primary)]"
        />
        <span>
          <span className="flex items-center gap-1.5 text-sm font-medium text-foreground">
            <Lock className="h-3.5 w-3.5" /> Pribadi
          </span>
          <span className="block text-xs text-muted">
            Nama & emoji disamarkan jadi “Kebiasaan pribadi” di dashboard, widget dan notifikasi. Di halaman Kebiasaan tetap
            terlihat.
          </span>
        </span>
      </label>

      <ErrorLine error={error} />

      <div className="flex flex-wrap items-center gap-2">
        {habit && !confirmDelete && (
          <>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              loading={pending && busy === "archive"}
              disabled={pending}
              onClick={() => run("archive", () => setHabitArchived(habit.id, !habit.archived))}
            >
              {habit.archived ? <ArchiveRestore className="h-4 w-4" /> : <Archive className="h-4 w-4" />}
              {habit.archived ? "Aktifkan lagi" : "Arsipkan"}
            </Button>
            <Button type="button" variant="ghost" size="sm" className="text-expense" disabled={pending} onClick={() => setConfirmDelete(true)}>
              <Trash2 className="h-4 w-4" /> Hapus
            </Button>
          </>
        )}
        <div className="ml-auto flex gap-2">
          <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
            Batal
          </Button>
          <Button type="submit" loading={pending && busy === "save"} disabled={pending}>
            {habit ? "Simpan" : "Buat kebiasaan"}
          </Button>
        </div>
      </div>

      {habit && confirmDelete && (
        <div className="rounded-xl border border-expense/40 bg-expense-soft p-3" role="alert">
          <p className="text-sm font-semibold text-expense">Hapus “{habit.name}”?</p>
          <p className="mt-1 text-xs text-foreground">
            Semua catatan, streak dan jurnalnya ikut terhapus permanen (juga di HP setelah sinkron). Kalau cuma mau jeda, pilih
            Arsipkan.
          </p>
          <div className="mt-3 flex justify-end gap-2">
            <Button type="button" variant="ghost" size="sm" onClick={() => setConfirmDelete(false)} disabled={pending}>
              Batal
            </Button>
            <Button
              type="button"
              variant="danger"
              size="sm"
              loading={pending && busy === "delete"}
              onClick={() => run("delete", () => deleteHabit(habit.id))}
            >
              Ya, hapus semuanya
            </Button>
          </div>
        </div>
      )}
    </form>
  );
}

function SegButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={cn(
        "h-9 rounded-lg border px-3 text-sm font-medium transition",
        active ? "border-primary bg-primary-soft text-primary" : "border-border bg-surface text-foreground hover:bg-accent",
      )}
    >
      {children}
    </button>
  );
}
