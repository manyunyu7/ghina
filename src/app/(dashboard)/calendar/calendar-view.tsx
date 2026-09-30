"use client";

import * as React from "react";
import Link from "next/link";
import { CalendarDays, ChevronLeft, ChevronRight, MapPin, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Field, Input, Label, Textarea } from "@/components/ui/input";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { localDateKey } from "@/lib/content";
import {
  allDayIso,
  DEFAULT_EVENT_COLOR,
  EVENT_COLORS,
  eventDayKeys,
  monthGridKeys,
  monthOf,
  monthRange,
  shiftMonth,
} from "@/lib/calendar";
import { CALENDAR_LOCATION_MAX, REMINDER_NOTES_MAX, REMINDER_TITLE_MAX } from "@/lib/schemas";
import { cn } from "@/lib/utils";
import {
  formatDateKey,
  formatTime,
  fromLocalInput,
  MONTHS_LONG,
  toLocalInput,
  useHydrated,
  useTimeZone,
  WEEKDAYS_LONG,
  WEEKDAYS_SHORT,
} from "../content/ui";
import { createCalendarEvent, deleteCalendarEvent, updateCalendarEvent, type CalendarEventInput } from "./actions";

export type CalendarEventDTO = {
  id: string;
  title: string;
  notes: string | null;
  startAt: string;
  endAt: string | null;
  allDay: boolean;
  color: string | null;
  location: string | null;
};

type Editing = { event: CalendarEventDTO | null; day: string };

const MAX_CHIPS = 3;
const monthHref = (m: string) => `/calendar?m=${m}`;
const weekdayOf = (key: string) => (new Date(`${key}T00:00:00Z`).getUTCDay() + 6) % 7;

export function CalendarView({ month, events }: { month: string; events: CalendarEventDTO[] }) {
  const tz = useTimeZone();
  const hydrated = useHydrated();
  const today = hydrated ? localDateKey(new Date(), tz) : null;
  const [selected, setSelected] = React.useState<string | null>(null);
  const [editing, setEditing] = React.useState<Editing | null>(null);

  const grid = React.useMemo(() => monthGridKeys(month), [month]);
  const byDay = React.useMemo(() => {
    const map = new Map<string, CalendarEventDTO[]>();
    for (const e of events) {
      for (const k of eventDayKeys(e, tz)) {
        const list = map.get(k);
        if (list) list.push(e);
        else map.set(k, [e]);
      }
    }
    // All-day first, then by start time.
    for (const list of map.values())
      list.sort((a, b) => Number(b.allDay) - Number(a.allDay) || a.startAt.localeCompare(b.startAt));
    return map;
  }, [events, tz]);

  const { first, last } = monthRange(month);
  const agendaDays = (selected ? [selected] : [...byDay.keys()].filter((k) => k >= first && k <= last)).sort();
  const [y, m] = month.split("-").map(Number);
  const defaultDay = selected ?? (today && monthOf(today) === month ? today : first);

  return (
    <div>
      <PageHeader
        title="Kalender"
        description="Jadwal dan acara kamu."
        action={
          <Button onClick={() => setEditing({ event: null, day: defaultDay })}>
            <Plus className="h-4 w-4" />
            Tambah acara
          </Button>
        }
      />

      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-1">
          <Link href={monthHref(shiftMonth(month, -1))} aria-label="Bulan sebelumnya" className="rounded-lg p-2 text-muted hover:bg-accent hover:text-foreground">
            <ChevronLeft className="h-5 w-5" />
          </Link>
          <h2 className="min-w-40 text-center text-lg font-semibold text-foreground">
            {MONTHS_LONG[m - 1]} {y}
          </h2>
          <Link href={monthHref(shiftMonth(month, 1))} aria-label="Bulan berikutnya" className="rounded-lg p-2 text-muted hover:bg-accent hover:text-foreground">
            <ChevronRight className="h-5 w-5" />
          </Link>
        </div>
        <Link href="/calendar" className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm font-medium text-foreground hover:bg-accent">
          Hari ini
        </Link>
      </div>

      <Card className="mb-6 overflow-hidden">
        <div className="grid grid-cols-7 border-b border-border bg-accent/50">
          {WEEKDAYS_SHORT.map((d) => (
            <div key={d} className="py-2 text-center text-xs font-semibold text-muted">
              {d}
            </div>
          ))}
        </div>
        <div className="grid grid-cols-7">
          {grid.map((key, i) => {
            const inMonth = monthOf(key) === month;
            const dayEvents = byDay.get(key) ?? [];
            const isToday = key === today;
            const isSelected = key === selected;
            return (
              <div
                key={key}
                role="button"
                tabIndex={0}
                aria-label={formatDateKey(key)}
                aria-pressed={isSelected}
                onClick={() => setSelected(isSelected ? null : key)}
                onKeyDown={(ev) => {
                  if (ev.key === "Enter" || ev.key === " ") {
                    ev.preventDefault();
                    setSelected(isSelected ? null : key);
                  }
                }}
                className={cn(
                  "min-h-16 cursor-pointer border-border-soft p-1 text-left outline-none transition hover:bg-accent/60 focus-visible:ring-2 focus-visible:ring-primary/40 sm:min-h-24 sm:p-1.5",
                  i % 7 !== 6 && "border-r",
                  i < 35 && "border-b",
                  !inMonth && "bg-accent/30",
                  isSelected && "bg-primary-soft hover:bg-primary-soft",
                )}
              >
                <span
                  className={cn(
                    "inline-flex h-6 w-6 items-center justify-center rounded-full text-xs font-medium",
                    isToday ? "bg-primary text-white" : inMonth ? "text-foreground" : "text-muted-soft",
                  )}
                >
                  {Number(key.slice(8))}
                </span>
                {/* Phones: dots; wider screens: chips. */}
                <div className="mt-0.5 flex flex-wrap gap-0.5 sm:hidden">
                  {dayEvents.slice(0, 4).map((e) => (
                    <span key={e.id} className="h-1.5 w-1.5 rounded-full" style={{ background: e.color ?? DEFAULT_EVENT_COLOR }} />
                  ))}
                </div>
                <div className="mt-0.5 hidden space-y-0.5 sm:block">
                  {dayEvents.slice(0, MAX_CHIPS).map((e) => (
                    <button
                      key={e.id}
                      type="button"
                      onClick={(ev) => {
                        ev.stopPropagation();
                        setEditing({ event: e, day: key });
                      }}
                      className="block w-full truncate rounded px-1 py-0.5 text-left text-[11px] font-medium text-white hover:opacity-90"
                      style={{ background: e.color ?? DEFAULT_EVENT_COLOR }}
                      title={e.title}
                    >
                      {!e.allDay && <span className="opacity-80">{formatTime(e.startAt, tz)} </span>}
                      {e.title}
                    </button>
                  ))}
                  {dayEvents.length > MAX_CHIPS && (
                    <p className="px-1 text-[11px] text-muted">+{dayEvents.length - MAX_CHIPS} lagi</p>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </Card>

      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-semibold text-foreground">
          Agenda {selected ? `· ${WEEKDAYS_LONG[weekdayOf(selected)]}, ${formatDateKey(selected)}` : `${MONTHS_LONG[m - 1]} ${y}`}
        </h2>
        <div className="flex gap-2">
          {selected && (
            <Button variant="ghost" size="sm" onClick={() => setSelected(null)}>
              Semua
            </Button>
          )}
          {selected && (
            <Button variant="outline" size="sm" onClick={() => setEditing({ event: null, day: selected })}>
              <Plus className="h-4 w-4" />
              Acara di hari ini
            </Button>
          )}
        </div>
      </div>

      {agendaDays.length === 0 || agendaDays.every((d) => !(byDay.get(d)?.length)) ? (
        <EmptyState icon={CalendarDays} title="Tidak ada acara" description={selected ? "Belum ada acara di hari ini." : "Belum ada acara di bulan ini."} />
      ) : (
        <div className="space-y-4">
          {agendaDays.map((day) => (
            <div key={day}>
              <p className={cn("mb-1.5 text-xs font-semibold uppercase tracking-wide", day === today ? "text-primary" : "text-muted")}>
                {WEEKDAYS_LONG[weekdayOf(day)]}, {formatDateKey(day)}
                {day === today && " · Hari ini"}
              </p>
              <Card className="divide-y divide-border-soft overflow-hidden">
                {(byDay.get(day) ?? []).map((e) => (
                  <button
                    key={e.id}
                    type="button"
                    onClick={() => setEditing({ event: e, day })}
                    className="flex w-full items-start gap-3 px-4 py-3 text-left hover:bg-accent"
                  >
                    <span className="mt-1 h-3 w-3 shrink-0 rounded-full" style={{ background: e.color ?? DEFAULT_EVENT_COLOR }} />
                    <div className="min-w-0 flex-1">
                      <p className="break-words text-sm font-medium text-foreground">{e.title}</p>
                      <p className="mt-0.5 text-xs text-muted">{timeLabel(e, day, tz)}</p>
                      {e.location && (
                        <p className="mt-0.5 inline-flex items-center gap-1 text-xs text-muted">
                          <MapPin className="h-3 w-3" />
                          {e.location}
                        </p>
                      )}
                      {e.notes && <p className="mt-1 whitespace-pre-wrap break-words text-xs text-muted-soft">{e.notes}</p>}
                    </div>
                  </button>
                ))}
              </Card>
            </div>
          ))}
        </div>
      )}

      <Modal open={editing !== null} onClose={() => setEditing(null)} title={editing?.event ? "Ubah acara" : "Acara baru"}>
        {editing && <EventForm event={editing.event} day={editing.day} onClose={() => setEditing(null)} />}
      </Modal>
    </div>
  );
}

/** "Sepanjang hari" / "09.00–10.30" / "Mulai 09.00" / "s.d. 10.30" for multi-day timed events. */
function timeLabel(e: CalendarEventDTO, day: string, tz: string): string {
  if (e.allDay) return "Sepanjang hari";
  const startDay = localDateKey(e.startAt, tz);
  const endDay = e.endAt ? localDateKey(e.endAt, tz) : startDay;
  const start = formatTime(e.startAt, tz);
  if (!e.endAt) return start;
  const end = formatTime(e.endAt, tz);
  if (startDay === endDay) return `${start}–${end}`;
  if (day === startDay) return `Mulai ${start}`;
  if (day === endDay) return `s.d. ${end}`;
  return "Sepanjang hari";
}

function EventForm({ event, day, onClose }: { event: CalendarEventDTO | null; day: string; onClose: () => void }) {
  const [allDay, setAllDay] = React.useState(event?.allDay ?? false);
  const [color, setColor] = React.useState(event?.color ?? DEFAULT_EVENT_COLOR);
  const [error, setError] = React.useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const [pending, startTransition] = React.useTransition();

  // Defaults: the event's own values, else `day` 09:00–10:00 (timed) / `day` (all-day).
  const dateDefaults = {
    start: event ? (event.allDay ? event.startAt.slice(0, 10) : toLocalInput(event.startAt).slice(0, 10)) : day,
    end: event?.endAt ? (event.allDay ? event.endAt.slice(0, 10) : toLocalInput(event.endAt).slice(0, 10)) : "",
  };
  const timeDefaults = {
    start: event ? (event.allDay ? `${event.startAt.slice(0, 10)}T09:00` : toLocalInput(event.startAt)) : `${day}T09:00`,
    end: event ? (event.endAt && !event.allDay ? toLocalInput(event.endAt) : "") : `${day}T10:00`,
  };

  function submit(ev: React.FormEvent<HTMLFormElement>) {
    ev.preventDefault();
    const fd = new FormData(ev.currentTarget);
    const s = (k: string) => String(fd.get(k) ?? "");
    let startAt: string | null;
    let endAt: string | null;
    if (allDay) {
      startAt = s("startDate") ? allDayIso(s("startDate")) : null;
      endAt = s("endDate") && s("endDate") !== s("startDate") ? allDayIso(s("endDate")) : null;
    } else {
      startAt = fromLocalInput(s("start"));
      endAt = fromLocalInput(s("end"));
    }
    if (!startAt) {
      setError("Waktu mulai tidak valid");
      return;
    }
    const input: CalendarEventInput = {
      title: s("title"),
      notes: s("notes"),
      location: s("location"),
      allDay,
      color,
      startAt,
      endAt,
    };
    setError(null);
    startTransition(async () => {
      const res = event ? await updateCalendarEvent(event.id, input) : await createCalendarEvent(input);
      if (res.ok) onClose();
      else setError(res.error);
    });
  }

  function remove() {
    if (!event) return;
    startTransition(async () => {
      const res = await deleteCalendarEvent(event.id);
      if (res.ok) onClose();
      else setError(res.error);
    });
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <Field label="Judul">
        <Input name="title" required maxLength={REMINDER_TITLE_MAX} autoFocus defaultValue={event?.title ?? ""} placeholder="mis. Rapat tim" />
      </Field>

      <label className="flex items-center gap-2 text-sm text-foreground">
        <input type="checkbox" checked={allDay} onChange={(e) => setAllDay(e.target.checked)} className="h-4 w-4 accent-[var(--color-primary)]" />
        Sepanjang hari
      </label>

      {allDay ? (
        <div className="grid grid-cols-2 gap-3">
          <Field label="Mulai">
            <Input key="sd" name="startDate" type="date" required defaultValue={dateDefaults.start} />
          </Field>
          <Field label="Sampai (opsional)">
            <Input key="ed" name="endDate" type="date" defaultValue={dateDefaults.end} />
          </Field>
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Mulai">
            <Input key="st" name="start" type="datetime-local" required defaultValue={timeDefaults.start} />
          </Field>
          <Field label="Selesai (opsional)">
            <Input key="et" name="end" type="datetime-local" defaultValue={timeDefaults.end} />
          </Field>
        </div>
      )}

      <Field label="Lokasi">
        <Input name="location" maxLength={CALENDAR_LOCATION_MAX} defaultValue={event?.location ?? ""} placeholder="Opsional" />
      </Field>

      <div>
        <Label>Warna</Label>
        <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Warna">
          {EVENT_COLORS.map((c) => (
            <button
              key={c}
              type="button"
              role="radio"
              aria-checked={color === c}
              aria-label={c}
              onClick={() => setColor(c)}
              className={cn("h-7 w-7 rounded-full ring-offset-2 ring-offset-card transition", color === c && "ring-2 ring-foreground")}
              style={{ background: c }}
            />
          ))}
        </div>
      </div>

      <Field label="Catatan">
        <Textarea name="notes" maxLength={REMINDER_NOTES_MAX} defaultValue={event?.notes ?? ""} placeholder="Opsional" />
      </Field>

      {error && <p className="text-sm text-expense">{error}</p>}

      <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
        <div>
          {event &&
            (confirmDelete ? (
              <div className="flex items-center gap-2">
                <span className="text-sm text-muted">Hapus acara?</span>
                <Button type="button" variant="danger" size="sm" onClick={remove} loading={pending}>
                  Hapus
                </Button>
                <Button type="button" variant="ghost" size="sm" onClick={() => setConfirmDelete(false)} disabled={pending}>
                  Batal
                </Button>
              </div>
            ) : (
              <Button type="button" variant="ghost" size="sm" onClick={() => setConfirmDelete(true)} disabled={pending}>
                <Trash2 className="h-4 w-4 text-expense" />
                Hapus
              </Button>
            ))}
        </div>
        <div className="flex gap-2">
          <Button type="button" variant="outline" onClick={onClose} disabled={pending}>
            Batal
          </Button>
          <Button type="submit" loading={pending && !confirmDelete}>
            Simpan
          </Button>
        </div>
      </div>
    </form>
  );
}
