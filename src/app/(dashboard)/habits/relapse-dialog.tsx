"use client";

import * as React from "react";
import { Plus, X } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Label, Textarea } from "@/components/ui/input";
import { HABIT_NOTE_MAX, HABIT_TRIGGER_MAX, HABIT_TRIGGERS_MAX, TRIGGER_PRESETS } from "@/lib/habits";
import type { ActionResult } from "@/lib/action-utils";
import { logRelapse, type RelapseInput } from "./actions";
import { Chip, ErrorLine } from "./parts";
import { browserTime } from "./format";

/** Preset + custom trigger chips (case-insensitive dedupe, ≤ 10). */
export function TriggerPicker({
  value,
  onChange,
  color,
  disabled,
}: {
  value: string[];
  onChange: (v: string[]) => void;
  color?: string;
  disabled?: boolean;
}) {
  const [custom, setCustom] = React.useState("");
  const has = (t: string) => value.some((v) => v.toLocaleLowerCase("id-ID") === t.toLocaleLowerCase("id-ID"));
  const toggle = (t: string) =>
    onChange(has(t) ? value.filter((v) => v.toLocaleLowerCase("id-ID") !== t.toLocaleLowerCase("id-ID")) : [...value, t]);
  const extra = value.filter((v) => !(TRIGGER_PRESETS as readonly string[]).includes(v.toLocaleLowerCase("id-ID")));
  const full = value.length >= HABIT_TRIGGERS_MAX;

  function add() {
    const t = custom.replace(/\s+/g, " ").trim().slice(0, HABIT_TRIGGER_MAX);
    if (!t || full) return;
    if (!has(t)) onChange([...value, t]);
    setCustom("");
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        {TRIGGER_PRESETS.map((t) => (
          <Chip key={t} active={has(t)} onClick={() => toggle(t)} color={color} disabled={disabled || (!has(t) && full)}>
            {t}
          </Chip>
        ))}
        {extra.map((t) => (
          <Chip key={t} active onClick={() => toggle(t)} color={color} disabled={disabled}>
            {t} <X className="h-3 w-3" aria-label="hapus" />
          </Chip>
        ))}
      </div>
      <div className="flex gap-2">
        <Input
          value={custom}
          onChange={(e) => setCustom(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              add();
            }
          }}
          maxLength={HABIT_TRIGGER_MAX}
          placeholder="Pemicu lain, mis. habis gajian"
          disabled={disabled || full}
          aria-label="Pemicu lain"
          className="h-9"
        />
        <Button type="button" variant="outline" size="sm" className="h-9" onClick={add} disabled={disabled || full || !custom.trim()}>
          <Plus className="h-4 w-4" /> Tambah
        </Button>
      </div>
    </div>
  );
}

export type RelapseFields = { triggers: string[]; note: string; date: string; time: string };

/** Triggers, note and when — shared by the relapse sheet and "Aku kalah kali ini". */
export function RelapseForm({
  today,
  color,
  previous,
  pending,
  error,
  showDate = true,
  submitLabel = "Simpan",
  onSubmit,
  onCancel,
}: {
  today: string;
  color: string;
  /** Current clean streak incl. today (a relapse today ends the run before today, shown as an achievement). */
  previous: number;
  pending: boolean;
  error: string | null;
  showDate?: boolean;
  submitLabel?: string;
  onSubmit: (f: RelapseFields) => void;
  onCancel: () => void;
}) {
  const [f, setF] = React.useState<RelapseFields>(() => ({ triggers: [], note: "", date: today, time: browserTime() }));
  // Today counts as clean "so far"; logging a relapse today ends the run at yesterday.
  const before = Math.max(0, previous - 1);
  return (
    <form
      className="space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit(f);
      }}
    >
      <div className="rounded-xl bg-accent/70 p-3 text-sm text-foreground">
        {before > 0 ? (
          <>
            Kamu sempat bersih <b>{before} hari</b> — itu nyata, dan nggak hilang. Catat dengan jujur, lalu mulai lagi. 🌱
          </>
        ) : (
          <>Nggak apa-apa. Kambuh itu data, bukan kegagalan. Catat dengan jujur supaya kamu bisa kenali polanya. 🌱</>
        )}
      </div>
      <div>
        <Label>Apa pemicunya? (opsional)</Label>
        <TriggerPicker value={f.triggers} onChange={(triggers) => setF((p) => ({ ...p, triggers }))} color={color} disabled={pending} />
      </div>
      <div>
        <Label htmlFor="relapse-note">Catatan (opsional)</Label>
        <Textarea
          id="relapse-note"
          value={f.note}
          maxLength={HABIT_NOTE_MAX}
          onChange={(e) => setF((p) => ({ ...p, note: e.target.value }))}
          placeholder="Lagi di mana, perasaan sebelumnya, apa yang bisa dicoba lain kali…"
          disabled={pending}
        />
      </div>
      <div className="grid grid-cols-2 gap-3">
        {showDate && (
          <div>
            <Label htmlFor="relapse-date">Tanggal</Label>
            <Input
              id="relapse-date"
              type="date"
              value={f.date}
              max={today}
              onChange={(e) => setF((p) => ({ ...p, date: e.target.value || today }))}
              disabled={pending}
            />
          </div>
        )}
        <div>
          <Label htmlFor="relapse-time">Jam</Label>
          <Input
            id="relapse-time"
            type="time"
            value={f.time}
            onChange={(e) => setF((p) => ({ ...p, time: e.target.value }))}
            disabled={pending}
          />
        </div>
      </div>
      <ErrorLine error={error} />
      <div className="flex justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onCancel} disabled={pending}>
          Batal
        </Button>
        <Button type="submit" loading={pending}>
          {submitLabel}
        </Button>
      </div>
    </form>
  );
}

/** Wire input from the form (local date + time → ISO instant). */
export function relapseInput(f: RelapseFields): RelapseInput {
  let at: string | null = null;
  if (f.time) {
    const d = new Date(`${f.date}T${f.time}`);
    if (!Number.isNaN(d.getTime())) at = d.toISOString();
  }
  return { date: f.date, triggers: f.triggers, note: f.note.trim() || null, at };
}

/** After logging: the previous streak as an achievement, the new one starts tomorrow. */
export function RelapseDone({ previousStreak, onClose }: { previousStreak: number; onClose: () => void }) {
  return (
    <div className="space-y-4 text-center">
      <div className="text-5xl" aria-hidden>
        🌱
      </div>
      {previousStreak > 0 ? (
        <p className="text-base font-semibold text-foreground">
          Kamu sempat bersih {previousStreak} hari — itu nyata.
        </p>
      ) : (
        <p className="text-base font-semibold text-foreground">Tercatat. Terima kasih sudah jujur.</p>
      )}
      <p className="text-sm text-muted">
        Satu hari berat nggak menghapus usahamu. Hari bersih barumu dimulai besok — pelan-pelan saja.
      </p>
      <Button className="w-full" onClick={onClose}>
        Oke, lanjut
      </Button>
    </div>
  );
}

/** "Aku kalah" sheet for quit habits. */
export function RelapseDialog({
  open,
  onClose,
  habitId,
  habitName,
  color,
  today,
  current,
}: {
  open: boolean;
  onClose: () => void;
  habitId: string;
  habitName: string;
  color: string;
  today: string;
  current: number;
}) {
  const [pending, startTransition] = React.useTransition();
  const [error, setError] = React.useState<string | null>(null);
  const [done, setDone] = React.useState<number | null>(null);

  function close() {
    if (pending) return;
    setError(null);
    setDone(null);
    onClose();
  }

  function submit(f: RelapseFields) {
    setError(null);
    startTransition(async () => {
      let res: ActionResult<{ previousStreak: number }>;
      try {
        res = await logRelapse(habitId, relapseInput(f));
      } catch {
        res = { ok: false, error: "Gagal menyimpan, periksa koneksi" };
      }
      if (res.ok) setDone(res.previousStreak);
      else setError(res.error);
    });
  }

  return (
    <Modal open={open} onClose={close} title={done == null ? "Aku kalah kali ini" : undefined} description={done == null ? habitName : undefined}>
      {done != null ? (
        <RelapseDone previousStreak={done} onClose={close} />
      ) : (
        <RelapseForm
          key={open ? "open" : "closed"}
          today={today}
          color={color}
          previous={current}
          pending={pending}
          error={error}
          onSubmit={submit}
          onCancel={close}
          submitLabel="Catat"
        />
      )}
    </Modal>
  );
}
