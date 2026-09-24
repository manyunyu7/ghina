"use client";

import * as React from "react";
import { Check, Clock, X, StickyNote } from "lucide-react";
import { cn } from "@/lib/utils";
import { SavingHint } from "@/components/ui/saving-hint";
import {
  FARDHU,
  SUNNAH,
  STATUSES,
  QUICK_STATUS,
  RAWATIB,
  SUNNAH_STATUS,
  UNFILLED,
  isPrayedStatus,
  rakaatOptions,
  statusInfo,
  type FardhuId,
  type SunnahId,
} from "@/lib/prayer-quality";
import { clearPrayer, savePrayer } from "./actions";
import type { PrayerEntryDTO } from "./types";

type Entries = Record<string, PrayerEntryDTO>;

/**
 * Edit one day: a status per fardhu (7 statuses; one-tap quick log = jamaah),
 * rawatib where they exist, daily sunnah with optional rakaat, optional time + note.
 * Optimistic; reverts and shows the error if the server rejects the change.
 */
export function PrayerDayEditor({
  dateKey,
  initial,
  readOnly = false,
}: {
  dateKey: string;
  initial: Entries;
  /** Future days can't be filled in. */
  readOnly?: boolean;
}) {
  const [entries, setEntries] = React.useState<Entries>(initial);
  const [error, setError] = React.useState<string | null>(null);
  const [pending, startTransition] = React.useTransition();

  function commit(prayer: string, next: PrayerEntryDTO | null) {
    const prev = entries[prayer] ?? null;
    setError(null);
    setEntries((cur) => {
      const copy = { ...cur };
      if (next) copy[prayer] = next;
      else delete copy[prayer];
      return copy;
    });
    startTransition(async () => {
      let res;
      try {
        res = next
          ? await savePrayer({
              date: dateKey,
              prayer,
              status: next.status,
              qobliyah: next.qobliyah,
              badiyah: next.badiyah,
              rakaat: next.rakaat,
              prayedAt: next.prayedAt,
              note: next.note,
            })
          : await clearPrayer({ date: dateKey, prayer });
      } catch {
        res = { ok: false as const, error: "Gagal menyimpan" };
      }
      if (!res.ok) {
        setError(res.error);
        setEntries((cur) => {
          const copy = { ...cur };
          if (prev) copy[prayer] = prev;
          else delete copy[prayer];
          return copy;
        });
      }
    });
  }

  const blank = (prayer: string, status: string): PrayerEntryDTO => ({
    date: dateKey,
    prayer,
    status,
    qobliyah: false,
    badiyah: false,
    rakaat: null,
    prayedAt: null,
    note: null,
  });

  function setStatus(prayer: FardhuId, status: string) {
    const cur = entries[prayer];
    const prayed = isPrayedStatus(status);
    const base = cur ?? blank(prayer, status);
    commit(prayer, {
      ...base,
      status,
      // Rawatib only go with a prayed status.
      qobliyah: prayed ? base.qobliyah : false,
      badiyah: prayed ? base.badiyah : false,
    });
  }

  const recorded = FARDHU.filter((p) => entries[p.id]).length;

  return (
    <div className="space-y-4">
      {readOnly && (
        <p className="rounded-lg bg-accent px-3 py-2 text-sm text-muted">Hari ini belum tiba — belum bisa diisi.</p>
      )}

      <div className="space-y-2">
        {FARDHU.map((p) => (
          <FardhuRow
            key={p.id}
            id={p.id}
            label={p.label}
            dateKey={dateKey}
            entry={entries[p.id] ?? null}
            disabled={readOnly}
            onStatus={(s) => setStatus(p.id, s)}
            onChange={(e) => commit(p.id, e)}
            onClear={() => commit(p.id, null)}
          />
        ))}
      </div>

      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">Shalat sunnah harian</p>
        <div className="grid gap-2 sm:grid-cols-3">
          {SUNNAH.map((s) => (
            <SunnahCard
              key={s.id}
              id={s.id}
              label={s.label}
              color={s.color}
              entry={entries[s.id] ?? null}
              disabled={readOnly}
              onToggle={() => commit(s.id, entries[s.id] ? null : blank(s.id, SUNNAH_STATUS))}
              onRakaat={(n) => commit(s.id, { ...(entries[s.id] ?? blank(s.id, SUNNAH_STATUS)), rakaat: n })}
            />
          ))}
        </div>
      </div>

      <div className="flex items-center justify-between text-xs text-muted">
        <span>
          {recorded}/{FARDHU.length} fardhu diisi
        </span>
        {error ? <span className="text-expense">{error}</span> : <SavingHint pending={pending} />}
      </div>
    </div>
  );
}

function FardhuRow({
  id,
  label,
  dateKey,
  entry,
  disabled,
  onStatus,
  onChange,
  onClear,
}: {
  id: FardhuId;
  label: string;
  dateKey: string;
  entry: PrayerEntryDTO | null;
  disabled: boolean;
  onStatus: (s: string) => void;
  onChange: (e: PrayerEntryDTO) => void;
  onClear: () => void;
}) {
  const [showDetails, setShowDetails] = React.useState(false);
  const info = entry ? statusInfo(entry.status) : null;
  const prayed = isPrayedStatus(entry?.status);
  const rawatib = RAWATIB[id];
  const hasDetails = Boolean(entry?.prayedAt || entry?.note);

  return (
    <div className="rounded-xl border border-border bg-surface p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span
          className="h-3 w-3 shrink-0 rounded-full"
          style={{ background: info?.color ?? UNFILLED.color }}
          aria-hidden
        />
        <span className="w-16 font-semibold text-foreground">{label}</span>
        <span className="flex-1 truncate text-sm text-muted">{info ? info.label : UNFILLED.label}</span>

        {!entry && !disabled && (
          <button
            type="button"
            onClick={() => onStatus(QUICK_STATUS)}
            className="inline-flex items-center gap-1 rounded-lg bg-income px-2.5 py-1 text-xs font-semibold text-white transition hover:opacity-90"
          >
            <Check className="h-3.5 w-3.5" /> Jamaah
          </button>
        )}
        {entry && !disabled && (
          <>
            <button
              type="button"
              onClick={() => setShowDetails((v) => !v)}
              className={cn(
                "rounded-lg p-1.5 text-muted transition hover:bg-accent hover:text-foreground",
                (showDetails || hasDetails) && "text-primary",
              )}
              aria-label="Waktu & catatan"
              title="Waktu & catatan"
            >
              {hasDetails && !showDetails ? <StickyNote className="h-4 w-4" /> : <Clock className="h-4 w-4" />}
            </button>
            <button
              type="button"
              onClick={onClear}
              className="rounded-lg p-1.5 text-muted transition hover:bg-accent hover:text-expense"
              aria-label={`Kosongkan ${label}`}
              title="Kosongkan"
            >
              <X className="h-4 w-4" />
            </button>
          </>
        )}
      </div>

      {/* Status chips */}
      <div className="mt-2 flex flex-wrap gap-1.5" role="radiogroup" aria-label={`Status ${label}`}>
        {STATUSES.map((s) => {
          const active = entry?.status === s.id;
          return (
            <button
              key={s.id}
              type="button"
              role="radio"
              aria-checked={active}
              disabled={disabled}
              onClick={() => onStatus(s.id)}
              title={s.label}
              className={cn(
                "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium transition disabled:opacity-50",
                active ? "border-transparent text-white shadow-sm" : "border-border text-muted hover:bg-accent hover:text-foreground",
              )}
              style={active ? { background: s.color } : undefined}
            >
              {!active && <span className="h-2 w-2 rounded-full" style={{ background: s.color }} />}
              {s.short}
            </button>
          );
        })}
      </div>

      {/* Rawatib */}
      {(rawatib.qobliyah || rawatib.badiyah) && (
        <div className="mt-2 flex flex-wrap gap-3 text-sm">
          {rawatib.qobliyah && (
            <RawatibCheck
              label="Qobliyah"
              checked={!!entry?.qobliyah}
              disabled={disabled || !prayed}
              onChange={(v) => entry && onChange({ ...entry, qobliyah: v })}
            />
          )}
          {rawatib.badiyah && (
            <RawatibCheck
              label="Ba'diyah"
              checked={!!entry?.badiyah}
              disabled={disabled || !prayed}
              onChange={(v) => entry && onChange({ ...entry, badiyah: v })}
            />
          )}
        </div>
      )}

      {entry && showDetails && !disabled && (
        <DetailsForm key={`${entry.prayedAt}|${entry.note}`} dateKey={dateKey} entry={entry} onSave={onChange} />
      )}
      {entry && !showDetails && hasDetails && (
        <p className="mt-2 truncate text-xs text-muted" suppressHydrationWarning>
          {entry.prayedAt && <>Pukul {timeOf(entry.prayedAt)}</>}
          {entry.prayedAt && entry.note && " · "}
          {entry.note}
        </p>
      )}
    </div>
  );
}

function RawatibCheck({
  label,
  checked,
  disabled,
  onChange,
}: {
  label: string;
  checked: boolean;
  disabled: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <label className={cn("inline-flex cursor-pointer items-center gap-1.5 text-muted", disabled && "cursor-not-allowed opacity-50")}>
      <input
        type="checkbox"
        className="h-4 w-4 accent-[var(--color-income)]"
        checked={checked}
        disabled={disabled}
        onChange={(e) => onChange(e.target.checked)}
      />
      {label}
    </label>
  );
}

function DetailsForm({
  dateKey,
  entry,
  onSave,
}: {
  dateKey: string;
  entry: PrayerEntryDTO;
  onSave: (e: PrayerEntryDTO) => void;
}) {
  const [time, setTime] = React.useState(entry.prayedAt ? timeOf(entry.prayedAt) : "");
  const [note, setNote] = React.useState(entry.note ?? "");

  function save() {
    const prayedAt = time ? atLocalTime(dateKey, time) : null;
    const n = note.trim() || null;
    if (prayedAt === entry.prayedAt && n === entry.note) return;
    onSave({ ...entry, prayedAt, note: n });
  }

  return (
    <div className="mt-3 grid gap-2 sm:grid-cols-[8rem_1fr]">
      <input
        type="time"
        value={time}
        onChange={(e) => setTime(e.target.value)}
        onBlur={save}
        aria-label="Waktu shalat"
        className="h-9 rounded-lg border border-border bg-surface px-2 text-sm text-foreground outline-none focus:border-primary"
      />
      <input
        type="text"
        value={note}
        maxLength={500}
        placeholder="Catatan (opsional)"
        onChange={(e) => setNote(e.target.value)}
        onBlur={save}
        onKeyDown={(e) => {
          if (e.key === "Enter") (e.target as HTMLInputElement).blur();
        }}
        className="h-9 rounded-lg border border-border bg-surface px-3 text-sm text-foreground outline-none placeholder:text-muted-soft focus:border-primary"
      />
    </div>
  );
}

function SunnahCard({
  id,
  label,
  color,
  entry,
  disabled,
  onToggle,
  onRakaat,
}: {
  id: SunnahId;
  label: string;
  color: string;
  entry: PrayerEntryDTO | null;
  disabled: boolean;
  onToggle: () => void;
  onRakaat: (n: number | null) => void;
}) {
  const done = Boolean(entry);
  return (
    <div
      className={cn("flex items-center gap-2 rounded-xl border p-2.5 transition", done ? "border-transparent" : "border-border bg-surface")}
      style={done ? { background: `${color}1f` } : undefined}
    >
      <button
        type="button"
        onClick={onToggle}
        disabled={disabled}
        aria-pressed={done}
        className="flex flex-1 items-center gap-2 text-left disabled:opacity-50"
      >
        <span
          className={cn("flex h-6 w-6 items-center justify-center rounded-full border transition", done ? "border-transparent text-white" : "border-border")}
          style={done ? { background: color } : undefined}
        >
          {done && <Check className="h-4 w-4" />}
        </span>
        <span className="text-sm font-medium text-foreground">{label}</span>
      </button>
      <select
        value={entry?.rakaat ?? ""}
        disabled={disabled || !done}
        onChange={(e) => onRakaat(e.target.value ? Number(e.target.value) : null)}
        aria-label={`Rakaat ${label}`}
        className="h-8 rounded-lg border border-border bg-surface px-1.5 text-xs text-foreground outline-none disabled:opacity-40"
      >
        <option value="">– rakaat</option>
        {rakaatOptions(id).map((n) => (
          <option key={n} value={n}>
            {n} rakaat
          </option>
        ))}
      </select>
    </div>
  );
}

/** ISO → "HH:MM" in local time. */
function timeOf(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/** Date key + "HH:MM" (local) → ISO. */
function atLocalTime(dateKey: string, hhmm: string): string {
  const [y, m, d] = dateKey.split("-").map(Number);
  const [hh, mm] = hhmm.split(":").map(Number);
  return new Date(y, m - 1, d, hh, mm).toISOString();
}
