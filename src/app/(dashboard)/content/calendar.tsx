"use client";

import * as React from "react";
import {
  DndContext,
  DragOverlay,
  KeyboardSensor,
  PointerSensor,
  TouchSensor,
  pointerWithin,
  rectIntersection,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  type CollisionDetection,
  type DragEndEvent,
} from "@dnd-kit/core";
import { CalendarDays, Check, ChevronLeft, ChevronRight, Loader2, Plus, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { localParts, platformLabel, postTime, weekSlots, weekStart, type WeekSlot } from "@/lib/content";
import { addDaysKey, daysInMonth } from "@/lib/tasks";
import { cn } from "@/lib/utils";
import { fetchContentCalendar, scheduleContentPost } from "./actions";
import { usePlanner } from "./planner";
import {
  AccountCode,
  formatDateKey,
  formatTime,
  handleText,
  MONTHS_LONG,
  Segmented,
  stageMovedText,
  useToast,
  WEEKDAYS_SHORT,
} from "./ui";
import type { CalendarData } from "@/lib/content-server";
import type { SocialAccountDTO } from "./types";

type CalPost = CalendarData["unscheduled"][number];
type View = "minggu" | "bulan";

class MousePointerSensor extends PointerSensor {
  static activators = [
    {
      eventName: "onPointerDown" as const,
      handler: ({ nativeEvent: e }: React.PointerEvent) => e.isPrimary && e.button === 0 && e.pointerType !== "touch",
    },
  ];
}
const collision: CollisionDetection = (args) => {
  const hits = pointerWithin(args);
  return hits.length ? hits : rectIntersection(args);
};

const HOURS = Array.from({ length: 24 }, (_, h) => h);
const DEFAULT_HOUR = 9;
const pad = (n: number) => String(n).padStart(2, "0");

/** Local instant (browser zone) for a date key + time. */
function localIso(dateKey: string, hour: number, minute: number): string {
  const [y, m, d] = dateKey.split("-").map(Number);
  return new Date(y, m - 1, d, hour, minute).toISOString();
}

function rangeFor(view: View, anchor: string): { from: string; to: string } {
  if (view === "minggu") {
    const from = weekStart(anchor);
    return { from, to: addDaysKey(from, 6) };
  }
  const [y, m] = anchor.split("-").map(Number);
  const first = `${y}-${pad(m)}-01`;
  const last = `${y}-${pad(m)}-${pad(daysInMonth(y, m))}`;
  return { from: weekStart(first), to: addDaysKey(weekStart(last), 6) };
}

export function ContentCalendar() {
  const { data, tz, version, mutate, openItem } = usePlanner();
  const toast = useToast();
  const today = localParts(new Date(), tz).date;
  const [view, setView] = React.useState<View>("minggu");
  const [anchor, setAnchor] = React.useState(today);
  const [cal, setCal] = React.useState<CalendarData | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [overrides, setOverrides] = React.useState<Map<string, string>>(() => new Map());
  const [dragging, setDragging] = React.useState<CalPost | null>(null);
  const [picker, setPicker] = React.useState<{ date: string; hour: number | null } | null>(null);
  const [accountFilter, setAccountFilter] = React.useState<string>("");
  const { from, to } = rangeFor(view, anchor);

  React.useEffect(() => {
    let alive = true;
    fetchContentCalendar({ from, to, timeZone: tz })
      .then((r) => {
        if (!alive) return;
        if (r.ok) {
          setCal(r.calendar);
          setOverrides(new Map());
          setError(null);
        } else setError(r.error);
      })
      .catch(() => alive && setError("Gagal memuat kalender"));
    return () => {
      alive = false;
    };
  }, [from, to, tz, version, data.posts]);

  const loading = !cal || cal.from !== from || cal.to !== to;
  const accounts = (cal?.accounts ?? data.accounts).filter((a) => !a.archived);
  const accById = React.useMemo(() => new Map((cal?.accounts ?? data.accounts).map((a) => [a.id, a])), [cal, data.accounts]);

  // Every post of the range (+ unscheduled drafts), with local drag overrides applied.
  const { byDay, byHour, unscheduled, all } = React.useMemo(() => {
    const posts: CalPost[] = [];
    const seen = new Set<string>();
    const add = (p: CalPost) => {
      if (seen.has(p.id)) return;
      seen.add(p.id);
      posts.push(p);
    };
    if (!loading && cal) {
      for (const d of cal.days) d.posts.forEach(add);
      cal.unscheduled.forEach(add);
    }
    const all = posts.map((p) => {
      const o = overrides.get(p.id);
      return o ? { ...p, scheduledAt: o, status: p.status === "draft" ? "scheduled" : p.status } : p;
    });
    const visible = all.filter((p) => !accountFilter || p.accountId === accountFilter);
    const byDay = new Map<string, CalPost[]>();
    const byHour = new Map<string, CalPost[]>();
    const unscheduled: CalPost[] = [];
    for (const p of visible) {
      const t = postTime(p);
      if (!t) {
        if (p.status !== "skipped") unscheduled.push(p);
        continue;
      }
      const lp = localParts(t, tz);
      byDay.set(lp.date, [...(byDay.get(lp.date) ?? []), p]);
      const k = `${lp.date}|${lp.hour}`;
      byHour.set(k, [...(byHour.get(k) ?? []), p]);
    }
    const time = (p: CalPost) => postTime(p)?.getTime() ?? 0;
    for (const list of [...byDay.values(), ...byHour.values()]) list.sort((a, b) => time(a) - time(b));
    return { byDay, byHour, unscheduled, all };
  }, [cal, loading, overrides, accountFilter, tz]);

  const weeks = React.useMemo(() => {
    const out: string[] = [];
    for (let w = from; w <= to; w = addDaysKey(w, 7)) out.push(w);
    return out;
  }, [from, to]);
  const slotsByWeek = React.useMemo(
    () => new Map(weeks.map((w) => [w, weekSlots(accounts, all, w, tz)])),
    [weeks, accounts, all, tz],
  );

  function reschedule(post: CalPost, date: string, hour: number | null) {
    if (post.status === "posted") return toast({ text: "Posting yang sudah tayang tidak bisa dijadwal ulang", tone: "info" });
    const cur = post.scheduledAt ? localParts(post.scheduledAt, tz) : null;
    const minute = post.scheduledAt ? new Date(post.scheduledAt).getMinutes() : 0;
    const iso = localIso(date, hour ?? cur?.hour ?? DEFAULT_HOUR, minute);
    if (post.scheduledAt && new Date(post.scheduledAt).getTime() === new Date(iso).getTime()) return;
    setOverrides((m) => new Map(m).set(post.id, iso));
    mutate(
      (s) => ({
        ...s,
        posts: s.posts.map((p) => (p.id === post.id ? { ...p, scheduledAt: iso, status: p.status === "draft" ? "scheduled" : p.status } : p)),
      }),
      async () => {
        const r = await scheduleContentPost(post.id, iso).catch(() => null);
        // Failure: the planner state rolls back, but no refetch follows — drop the override here.
        if (!r?.ok)
          setOverrides((m) => {
            if (m.get(post.id) !== iso) return m;
            const n = new Map(m);
            n.delete(post.id);
            return n;
          });
        return r ?? { ok: false as const, error: "Terjadi kesalahan, coba lagi" };
      },
      (r) => {
        const moved = stageMovedText(r.stage);
        toast({ text: [`Dijadwalkan ${formatDateKey(date, false)} ${formatTime(iso, tz)}`, moved].filter(Boolean).join(" · "), tone: "success" });
      },
    );
  }

  const sensors = useSensors(
    useSensor(MousePointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 220, tolerance: 8 } }),
    useSensor(KeyboardSensor, { keyboardCodes: { start: ["Space"], cancel: ["Escape"], end: ["Space", "Enter"] } }),
  );

  function onDragEnd(e: DragEndEvent) {
    setDragging(null);
    const over = e.over ? String(e.over.id) : null;
    const post = all.find((p) => `post:${p.id}` === String(e.active.id));
    if (!over || !post) return;
    const [kind, date, hour] = over.split("|");
    if (kind === "slot") reschedule(post, date, Number(hour));
    else if (kind === "day") reschedule(post, date, null);
  }

  function shift(dir: -1 | 1) {
    if (view === "minggu") setAnchor((a) => addDaysKey(a, 7 * dir));
    else {
      const [y, m] = anchor.split("-").map(Number);
      const d = new Date(y, m - 1 + dir, 1);
      setAnchor(`${d.getFullYear()}-${pad(d.getMonth() + 1)}-01`);
    }
  }

  const title =
    view === "minggu"
      ? `${formatDateKey(from, from.slice(0, 4) !== to.slice(0, 4))} – ${formatDateKey(to)}`
      : `${MONTHS_LONG[Number(anchor.slice(5, 7)) - 1]} ${anchor.slice(0, 4)}`;

  const hintWeek = view === "minggu" ? from : weekStart(today >= from && today <= to ? today : from);
  const hintSlots = (slotsByWeek.get(hintWeek) ?? []).filter((s) => s.empty);

  return (
    <div>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <div className="flex items-center gap-1">
          <Button variant="outline" size="icon" onClick={() => shift(-1)} aria-label={view === "minggu" ? "Minggu sebelumnya" : "Bulan sebelumnya"}>
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="icon" onClick={() => shift(1)} aria-label={view === "minggu" ? "Minggu berikutnya" : "Bulan berikutnya"}>
            <ChevronRight className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setAnchor(today)}>
            Hari ini
          </Button>
        </div>
        <h2 className="text-base font-semibold text-foreground" aria-live="polite">
          {title}
        </h2>
        {loading && <Loader2 className="h-4 w-4 animate-spin text-muted" aria-label="Memuat" />}
        <div className="ml-auto flex flex-wrap items-center gap-2">
          {accounts.length > 1 && (
            <select
              aria-label="Filter akun"
              value={accountFilter}
              onChange={(e) => setAccountFilter(e.target.value)}
              className="h-9 rounded-lg border border-border bg-surface px-2 text-sm"
            >
              <option value="">Semua akun</option>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {platformLabel(a)} {handleText(a.handle)}
                </option>
              ))}
            </select>
          )}
          <Segmented
            label="Tampilan kalender"
            value={view}
            onChange={setView}
            options={[
              { id: "minggu", label: "Minggu" },
              { id: "bulan", label: "Bulan" },
            ]}
          />
        </div>
      </div>

      {error && (
        <p role="alert" className="mb-3 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          {error}
        </p>
      )}

      {view === "minggu" && <TargetMeters slots={slotsByWeek.get(from) ?? []} accById={accById} />}
      {hintSlots.length > 0 && (
        <p className="mb-3 text-xs text-muted">
          💡 {hintSlots.map((s) => `${short(accById.get(s.accountId))} kurang ${s.empty}`).join(", ")} posting{" "}
          {hintWeek === weekStart(today) ? "minggu ini" : "di minggu itu"} — klik slot kosong atau seret konten dari “Belum dijadwalkan”.
        </p>
      )}

      <DndContext
        id="content-calendar"
        sensors={sensors}
        collisionDetection={collision}
        onDragStart={(e) => setDragging(all.find((p) => `post:${p.id}` === String(e.active.id)) ?? null)}
        onDragCancel={() => setDragging(null)}
        onDragEnd={onDragEnd}
      >
        {view === "minggu" ? (
          <WeekGrid from={from} today={today} byHour={byHour} accById={accById} onOpen={(p) => openItem({ mode: "edit", id: p.contentId })} onPick={setPicker} />
        ) : (
          <MonthGrid
            weeks={weeks}
            month={anchor.slice(0, 7)}
            today={today}
            byDay={byDay}
            slotsByWeek={slotsByWeek}
            accById={accById}
            onOpen={(p) => openItem({ mode: "edit", id: p.contentId })}
            onPick={setPicker}
          />
        )}

        <section className="mt-4 rounded-card border border-border bg-surface/60 p-3" aria-labelledby="unscheduled-h">
          <h3 id="unscheduled-h" className="mb-2 text-sm font-semibold text-foreground">
            Belum dijadwalkan <span className="font-normal text-muted">({unscheduled.length})</span>
          </h3>
          {unscheduled.length === 0 ? (
            <p className="text-xs text-muted">
              {accounts.length === 0
                ? "Tambah akun dulu di Pengaturan, lalu tambahkan posting per akun di konten."
                : "Semua posting sudah punya jadwal. Posting draf tanpa jadwal muncul di sini untuk diseret ke kalender."}
            </p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {unscheduled.map((p) => (
                <DraggableChip key={p.id} post={p} account={accById.get(p.accountId)} tz={tz} onOpen={() => openItem({ mode: "edit", id: p.contentId })} wide />
              ))}
            </div>
          )}
        </section>

        <DragOverlay dropAnimation={null}>{dragging ? <ChipBody post={dragging} account={accById.get(dragging.accountId)} tz={tz} overlay /> : null}</DragOverlay>
      </DndContext>

      {picker && (
        <SlotPicker
          slot={picker}
          posts={unscheduled}
          accById={accById}
          onClose={() => setPicker(null)}
          onPick={(p) => {
            setPicker(null);
            reschedule(p, picker.date, picker.hour);
          }}
        />
      )}
    </div>
  );
}

const short = (a: SocialAccountDTO | undefined) => (a ? (a.platform === "other" ? a.platformName ?? "Lainnya" : platformLabel(a)) : "?");

function TargetMeters({ slots, accById }: { slots: WeekSlot[]; accById: Map<string, SocialAccountDTO> }) {
  const withTarget = slots.filter((s) => s.target);
  if (!slots.length) return null;
  return (
    <div className="mb-3 flex flex-wrap gap-2" aria-label="Target mingguan">
      {slots.map((s) => {
        const a = accById.get(s.accountId);
        if (!a) return null;
        const pct = s.target ? Math.min(100, (s.planned / s.target) * 100) : 0;
        return (
          <div key={s.accountId} className="min-w-[128px] rounded-lg border border-border bg-card px-2.5 py-1.5">
            <div className="flex items-center gap-1.5 text-xs">
              <AccountCode account={a} />
              <span className="truncate text-muted">{handleText(a.handle)}</span>
              <span className={cn("ml-auto font-semibold tabular-nums", s.met ? "text-income" : "text-foreground")}>
                {s.target ? `${s.planned}/${s.target}` : s.planned}
                {s.met && <Check className="ml-0.5 inline h-3 w-3" aria-label="Target tercapai" />}
              </span>
            </div>
            {s.target ? (
              <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-accent" title={`${s.posted} sudah tayang, ${s.planned} direncanakan dari target ${s.target}`}>
                <div className="h-full rounded-full" style={{ width: `${pct}%`, background: a.color }} />
              </div>
            ) : (
              <p className="mt-0.5 text-[10px] text-muted-soft">tanpa target</p>
            )}
          </div>
        );
      })}
      {withTarget.length === 0 && <p className="self-center text-xs text-muted">Atur target per minggu di Pengaturan untuk melihat slot kosong.</p>}
    </div>
  );
}

function WeekGrid({
  from,
  today,
  byHour,
  accById,
  onOpen,
  onPick,
}: {
  from: string;
  today: string;
  byHour: Map<string, CalPost[]>;
  accById: Map<string, SocialAccountDTO>;
  onOpen: (p: CalPost) => void;
  onPick: (s: { date: string; hour: number | null }) => void;
}) {
  const { tz } = usePlanner();
  const days = Array.from({ length: 7 }, (_, i) => addDaysKey(from, i));
  const scroller = React.useRef<HTMLDivElement>(null);
  React.useEffect(() => {
    // Start at 06:00 (rows are ~44px).
    if (scroller.current) scroller.current.scrollTop = 6 * 44;
  }, []);
  return (
    <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
      <div ref={scroller} className="max-h-[65vh] min-w-[760px] overflow-y-auto rounded-card border border-border bg-card">
        <div className="grid grid-cols-[44px_repeat(7,minmax(100px,1fr))]">
          <div className="sticky top-0 z-10 border-b border-border bg-card" />
          {days.map((d, i) => (
            <div
              key={d}
              className={cn("sticky top-0 z-10 border-b border-l border-border bg-card px-2 py-1.5 text-center text-xs", d === today && "text-primary")}
            >
              <span className="font-medium">{WEEKDAYS_SHORT[i]}</span>{" "}
              <span className={cn("inline-flex h-6 min-w-6 items-center justify-center rounded-full px-1 font-semibold", d === today && "bg-primary text-white")}>
                {Number(d.slice(8))}
              </span>
            </div>
          ))}
          {HOURS.map((h) => (
            <React.Fragment key={h}>
              <div className="border-b border-border-soft pr-1 pt-0.5 text-right text-[10px] tabular-nums text-muted-soft">{pad(h)}.00</div>
              {days.map((d) => (
                <SlotCell key={d} id={`slot|${d}|${h}`} label={`${formatDateKey(d, false)} ${pad(h)}.00`} empty={!byHour.get(`${d}|${h}`)?.length} onPick={() => onPick({ date: d, hour: h })} className="min-h-11 border-b border-l border-border-soft p-0.5">
                  {(byHour.get(`${d}|${h}`) ?? []).map((p) => (
                    <DraggableChip key={p.id} post={p} account={accById.get(p.accountId)} tz={tz} onOpen={() => onOpen(p)} />
                  ))}
                </SlotCell>
              ))}
            </React.Fragment>
          ))}
        </div>
      </div>
    </div>
  );
}

function MonthGrid({
  weeks,
  month,
  today,
  byDay,
  slotsByWeek,
  accById,
  onOpen,
  onPick,
}: {
  weeks: string[];
  month: string;
  today: string;
  byDay: Map<string, CalPost[]>;
  slotsByWeek: Map<string, WeekSlot[]>;
  accById: Map<string, SocialAccountDTO>;
  onOpen: (p: CalPost) => void;
  onPick: (s: { date: string; hour: number | null }) => void;
}) {
  const { tz } = usePlanner();
  const MAX = 3;
  return (
    <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
      <div className="min-w-[700px] overflow-hidden rounded-card border border-border bg-card">
        <div className="grid grid-cols-7 border-b border-border">
          {WEEKDAYS_SHORT.map((d) => (
            <div key={d} className="px-2 py-1.5 text-center text-xs font-medium text-muted">
              {d}
            </div>
          ))}
        </div>
        {weeks.map((w) => {
          const slots = (slotsByWeek.get(w) ?? []).filter((s) => s.target);
          return (
            <div key={w} className="border-b border-border last:border-b-0">
              {slots.length > 0 && (
                <div className="flex flex-wrap gap-x-3 gap-y-0.5 bg-surface/60 px-2 py-1 text-[11px]">
                  {slots.map((s) => {
                    const a = accById.get(s.accountId);
                    return a ? (
                      <span key={s.accountId} className={cn("inline-flex items-center gap-1 tabular-nums", s.met ? "text-income" : s.empty ? "text-muted" : "text-foreground")}>
                        <AccountCode account={a} />
                        {s.planned}/{s.target}
                        {s.met && <Check className="h-3 w-3" aria-label="Target tercapai" />}
                      </span>
                    ) : null;
                  })}
                </div>
              )}
              <div className="grid grid-cols-7">
                {Array.from({ length: 7 }, (_, i) => addDaysKey(w, i)).map((d) => {
                  const list = byDay.get(d) ?? [];
                  const out = d.slice(0, 7) !== month;
                  return (
                    <SlotCell
                      key={d}
                      id={`day|${d}`}
                      label={formatDateKey(d, false)}
                      empty={list.length === 0}
                      onPick={() => onPick({ date: d, hour: null })}
                      className={cn("min-h-28 border-l border-border-soft p-1 first:border-l-0", out && "bg-accent/40")}
                    >
                      <span
                        className={cn(
                          "mb-0.5 inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[11px] font-semibold",
                          d === today ? "bg-primary text-white" : out ? "text-muted-soft" : "text-foreground",
                        )}
                      >
                        {Number(d.slice(8))}
                      </span>
                      {list.slice(0, MAX).map((p) => (
                        <DraggableChip key={p.id} post={p} account={accById.get(p.accountId)} tz={tz} onOpen={() => onOpen(p)} />
                      ))}
                      {list.length > MAX && <MoreList posts={list.slice(MAX)} accById={accById} onOpen={onOpen} />}
                    </SlotCell>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function MoreList({ posts, accById, onOpen }: { posts: CalPost[]; accById: Map<string, SocialAccountDTO>; onOpen: (p: CalPost) => void }) {
  const { tz } = usePlanner();
  const [open, setOpen] = React.useState(false);
  if (open)
    return (
      <>
        {posts.map((p) => (
          <DraggableChip key={p.id} post={p} account={accById.get(p.accountId)} tz={tz} onOpen={() => onOpen(p)} />
        ))}
      </>
    );
  return (
    <button type="button" onClick={() => setOpen(true)} className="w-full rounded px-1 text-left text-[11px] font-medium text-muted hover:bg-accent">
      +{posts.length} lagi
    </button>
  );
}

function SlotCell({ id, label, empty, onPick, className, children }: { id: string; label: string; empty: boolean; onPick: () => void; className?: string; children: React.ReactNode }) {
  const { setNodeRef, isOver } = useDroppable({ id });
  return (
    <div
      ref={setNodeRef}
      data-slot={id}
      className={cn("group relative flex min-w-0 flex-col gap-0.5 transition-colors", isOver && "bg-primary-soft", className)}
      onClick={(e) => {
        if (e.target === e.currentTarget) onPick();
      }}
    >
      {children}
      {empty && (
        <button
          type="button"
          onClick={onPick}
          aria-label={`Jadwalkan di ${label}`}
          className="absolute bottom-0.5 right-0.5 hidden rounded p-0.5 text-muted-soft hover:bg-accent hover:text-primary focus-visible:block group-hover:block"
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );
}

function DraggableChip({ post, account, tz, onOpen, wide }: { post: CalPost; account?: SocialAccountDTO; tz: string; onOpen: () => void; wide?: boolean }) {
  const posted = post.status === "posted";
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: `post:${post.id}`, disabled: posted });
  return (
    <button
      ref={setNodeRef}
      type="button"
      data-post={post.id}
      {...attributes}
      {...listeners}
      onClick={onOpen}
      aria-label={`${post.title} — ${account ? `${platformLabel(account)} ${handleText(account.handle)}` : ""}${posted ? " (sudah tayang)" : ""}`}
      className={cn("block w-full min-w-0 text-left outline-none focus-visible:ring-2 focus-visible:ring-primary/50 rounded-md", wide && "w-auto max-w-full", isDragging && "opacity-30", !posted && "cursor-grab touch-manipulation")}
    >
      <ChipBody post={post} account={account} tz={tz} />
    </button>
  );
}

function ChipBody({ post, account, tz, overlay }: { post: CalPost; account?: SocialAccountDTO; tz: string; overlay?: boolean }) {
  const color = account?.color ?? "#8E8E93";
  const t = postTime(post);
  const posted = post.status === "posted";
  const skipped = post.status === "skipped";
  return (
    <span
      className={cn(
        "flex min-w-0 items-center gap-1 rounded-md border-l-[3px] px-1.5 py-0.5 text-[11px] leading-4 text-foreground",
        overlay && "shadow-lg",
        skipped && "opacity-50 line-through",
      )}
      style={{ borderColor: color, background: `${color}${posted ? "30" : "18"}` }}
    >
      {posted && <Check className="h-3 w-3 shrink-0 text-income" aria-hidden />}
      {t && <span className="shrink-0 tabular-nums text-muted">{formatTime(t.toISOString(), tz)}</span>}
      {account && <AccountCode account={account} className="bg-transparent px-0" />}
      <span className="min-w-0 truncate font-medium">{post.title || "Tanpa judul"}</span>
    </span>
  );
}

function SlotPicker({
  slot,
  posts,
  accById,
  onClose,
  onPick,
}: {
  slot: { date: string; hour: number | null };
  posts: CalPost[];
  accById: Map<string, SocialAccountDTO>;
  onClose: () => void;
  onPick: (p: CalPost) => void;
}) {
  const { openItem } = usePlanner();
  const when = `${formatDateKey(slot.date)}${slot.hour != null ? `, ${pad(slot.hour)}.00` : ` (jam ${pad(DEFAULT_HOUR)}.00)`}`;
  return (
    <Modal open onClose={onClose} title="Jadwalkan di slot ini" description={when}>
      {posts.length === 0 ? (
        <div className="space-y-3 text-sm text-muted">
          <p>Tidak ada posting draf tanpa jadwal. Buat konten baru, tambahkan posting per akun, lalu atur jadwalnya.</p>
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={onClose}>
              <X className="h-4 w-4" /> Tutup
            </Button>
            <Button
              onClick={() => {
                onClose();
                openItem({ mode: "create", stage: "ide" });
              }}
            >
              <Plus className="h-4 w-4" /> Konten baru
            </Button>
          </div>
        </div>
      ) : (
        <ul className="space-y-1.5">
          {posts.map((p) => {
            const a = accById.get(p.accountId);
            return (
              <li key={p.id}>
                <button
                  type="button"
                  onClick={() => onPick(p)}
                  className="flex w-full items-center gap-2 rounded-lg border border-border px-3 py-2 text-left text-sm transition hover:border-primary hover:bg-primary-soft/40"
                >
                  <CalendarDays className="h-4 w-4 shrink-0 text-muted" />
                  <span className="min-w-0 flex-1 truncate font-medium text-foreground">{p.title}</span>
                  {a && <AccountCode account={a} />}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </Modal>
  );
}
