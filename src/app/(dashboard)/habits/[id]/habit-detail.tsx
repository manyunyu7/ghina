"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowLeft, ChevronLeft, ChevronRight, Lock, Pencil, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Textarea } from "@/components/ui/input";
import { Badge } from "@/components/ui/misc";
import { LinkPending, LinkPendingIcon } from "@/components/link-pending";
import { cn } from "@/lib/utils";
import {
  HABIT_NOTE_MAX,
  HABIT_XP,
  nextQuitMilestone,
  quitMilestonesReached,
  type HabitInsights,
  type HabitLogType,
  type HeatmapDay,
} from "@/lib/habits";
import type { HabitDetail, HabitLogDTO } from "@/lib/habits-server";
import { isoWeekday } from "@/lib/tasks";
import { deleteHabitLog, setHabitLogNote } from "../actions";
import { HabitCard } from "../habit-card";
import { HabitFormDialog } from "../habit-form";
import { ErrorLine, HabitAvatar, ProgressRing } from "../parts";
import {
  LOG_TYPE_LABEL,
  MONTHS_LONG,
  MONTHS_SHORT,
  WEEKDAYS_SHORT,
  fmtNum,
  formatDay,
  progressLabel,
  scheduleLabel,
  targetLabel,
} from "../format";
import { useBlurNames, useBrowserToday } from "../hooks";
import { GroupedBars, StreakHistoryChart } from "./charts";

type Range = { view: "month" | "year"; from: string; to: string; year: number; month: number };

const RELAPSE_COLOR = "#ef4444";
const URGE_COLOR = "#f59e0b";

export function HabitDetailView({
  detail,
  today,
  timeZone,
  canSkipToday,
  range,
}: {
  detail: HabitDetail;
  today: string;
  timeZone?: string;
  canSkipToday: boolean;
  range: Range;
}) {
  useBrowserToday(today, timeZone, true);
  const router = useRouter();
  const [blur] = useBlurNames();
  const [editing, setEditing] = React.useState(false);
  const { habit, insights, logs } = detail;
  const quit = habit.kind === "quit";
  const item = { ...habit, today: detail.today };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex min-w-0 items-center gap-3">
          <HabitAvatar emoji={habit.emoji} name={habit.name} color={habit.color} size="lg" />
          <div className="min-w-0">
            <Link href="/habits" className="inline-flex items-center gap-1 text-xs font-medium text-muted hover:text-foreground">
              <LinkPendingIcon className="h-3.5 w-3.5">
                <ArrowLeft className="h-3.5 w-3.5" />
              </LinkPendingIcon>
              Kebiasaan
            </Link>
            <h1
              className={cn(
                "flex items-center gap-2 text-2xl font-bold tracking-tight text-foreground [overflow-wrap:anywhere]",
                blur && "select-none blur-[8px] hover:blur-none",
              )}
            >
              {habit.name}
            </h1>
            <p className="flex flex-wrap items-center gap-x-2 text-sm text-muted">
              <span>{quit ? "Berhenti · setiap hari" : `${scheduleLabel(habit.schedule)} · ${targetLabel(habit.target)}`}</span>
              <span>· sejak {formatDay(habit.startDate)}</span>
              {habit.private && (
                <span className="inline-flex items-center gap-1">
                  · <Lock className="h-3.5 w-3.5" /> Pribadi
                </span>
              )}
              {habit.archived && <Badge>Diarsipkan</Badge>}
            </p>
          </div>
        </div>
        <Button variant="outline" onClick={() => setEditing(true)}>
          <Pencil className="h-4 w-4" /> Ubah
        </Button>
      </div>

      {habit.why && (
        <div className="rounded-card border border-border bg-card p-4">
          <p className="text-xs font-semibold text-muted">{quit ? "Alasan aku berhenti" : "Alasan aku mulai"}</p>
          <p className="mt-1 whitespace-pre-line text-sm text-foreground">{habit.why}</p>
        </div>
      )}

      {/* Today + streak */}
      <div className="grid gap-4 lg:grid-cols-3">
        <HabitCard item={item} today={today} canSkipToday={canSkipToday} detailLink={false} refreshAfter />
        <StreakCard insights={insights} color={habit.color} quit={quit} />
        <CompletionCard insights={insights} quit={quit} range={range} color={habit.color} />
      </div>

      {/* Range picker + heatmap */}
      <Card className="min-w-0">
        <CardHeader className="flex-wrap gap-3">
          <CardTitle>Kalender</CardTitle>
          <RangeNav range={range} today={today} timeZone={timeZone} />
        </CardHeader>
        <CardContent>
          {range.view === "month" ? (
            <MonthHeatmap days={insights.heatmap} color={habit.color} today={today} quit={quit} goalLabel={(d) => dayTitle(d, habit, quit)} />
          ) : (
            <YearHeatmap days={insights.heatmap} color={habit.color} today={today} goalLabel={(d) => dayTitle(d, habit, quit)} />
          )}
          <Legend color={habit.color} quit={quit} />
        </CardContent>
      </Card>

      <StreakHistory insights={insights} color={habit.color} quit={quit} weekly={habit.schedule.type === "perWeek" && !quit} />

      {quit ? <QuitInsights insights={insights} /> : <BuildInsights insights={insights} color={habit.color} />}

      <LogList logs={logs} habit={habit} today={today} onChanged={() => router.refresh()} />

      {editing && (
        <HabitFormDialog
          target={{ mode: "edit", habit }}
          today={today}
          onClose={() => {
            setEditing(false);
            router.refresh();
          }}
          onDeleted={() => router.push("/habits")}
        />
      )}
    </div>
  );
}

// ---------- Streak + milestones ----------

function StreakCard({ insights, color, quit }: { insights: HabitInsights; color: string; quit: boolean }) {
  const s = insights.streak;
  const unit = s.unit === "week" ? "minggu" : "hari";
  let milestones: number[];
  let next: number;
  if (quit) {
    next = nextQuitMilestone(s.current);
    const reached = quitMilestonesReached(s.current);
    milestones = [...reached.slice(-3), next];
  } else {
    const keys = Object.keys(HABIT_XP.buildStreakBonus).map(Number);
    next = keys.find((k) => k > s.current) ?? (Math.floor(s.current / 100) + 1) * 100;
    milestones = [...keys.filter((k) => k <= s.current).slice(-3), next];
  }
  const prev = milestones.length > 1 ? milestones[milestones.length - 2] : 0;
  const pct = next > prev ? (s.current - prev) / (next - prev) : 1;
  return (
    <Card>
      <CardContent className="flex flex-col items-center gap-4 sm:flex-row lg:flex-col xl:flex-row">
        <ProgressRing value={s.current / next} color={color} size={128} stroke={11} label={`Streak ${s.current} ${unit}`}>
          <span className="text-4xl font-bold tabular-nums text-foreground">{s.current}</span>
          <span className="text-xs text-muted">{quit ? "hari bersih" : `${unit} beruntun`}</span>
        </ProgressRing>
        <div className="w-full min-w-0 flex-1 space-y-3">
          <div>
            <p className="text-xs text-muted">Terlama</p>
            <p className="text-xl font-bold tabular-nums text-foreground">
              {s.longest} <span className="text-sm font-medium text-muted">{unit}</span>
            </p>
          </div>
          <div>
            <p className="mb-1 text-xs text-muted">
              Menuju {next} {unit} · {Math.max(0, next - s.current)} lagi
            </p>
            <div className="h-2 overflow-hidden rounded-full bg-accent">
              <div className="h-full rounded-full transition-all" style={{ width: `${Math.round(pct * 100)}%`, background: color }} />
            </div>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {milestones.map((m) => {
              const hit = s.current >= m;
              return (
                <span
                  key={m}
                  className={cn("rounded-full px-2 py-0.5 text-xs font-semibold", hit ? "text-white" : "border border-dashed border-border text-muted")}
                  style={hit ? { background: color } : undefined}
                >
                  {hit ? "🏅 " : ""}
                  {m}
                </span>
              );
            })}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function CompletionCard({ insights, quit, range, color }: { insights: HabitInsights; quit: boolean; range: Range; color: string }) {
  const c = insights.completion;
  const pct = c.rate == null ? null : Math.round(c.rate * 100);
  const label = range.view === "year" ? `Tahun ${range.year}` : `${MONTHS_LONG[range.month - 1]} ${range.year}`;
  const weekly = insights.weeks.length > 0;
  return (
    <Card>
      <CardContent className="space-y-4">
        <div>
          <p className="text-xs text-muted">{quit ? "Hari bersih" : "Tingkat keberhasilan"} · {label}</p>
          <p className="mt-1 text-4xl font-bold tabular-nums text-foreground">{pct == null ? "–" : `${pct}%`}</p>
          <p className="text-xs text-muted">
            {c.total === 0
              ? "Belum ada hari yang dihitung di rentang ini."
              : quit
                ? `${c.met} dari ${c.total} hari tanpa kambuh`
                : `${c.met} dari ${c.total} ${weekly ? "minggu" : "hari terjadwal"} tercapai`}
          </p>
          <div className="mt-2 h-2 overflow-hidden rounded-full bg-accent">
            <div className="h-full rounded-full" style={{ width: `${pct ?? 0}%`, background: color }} />
          </div>
        </div>
        {quit && (
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-xl bg-accent/70 p-3">
              <p className="text-xs text-muted">Pengen, tapi tahan</p>
              <p className="text-2xl font-bold tabular-nums text-foreground">{insights.urges.total} 💪</p>
            </div>
            <div className="rounded-xl bg-accent/70 p-3">
              <p className="text-xs text-muted">Kambuh</p>
              <p className="text-2xl font-bold tabular-nums text-foreground">{insights.relapses.total}</p>
              <p className="text-[11px] text-muted">{insights.relapses.days} hari</p>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ---------- Range nav ----------

function RangeNav({ range, today, timeZone }: { range: Range; today: string; timeZone?: string }) {
  const [ty, tm] = today.split("-").map(Number);
  const extra = (q: URLSearchParams) => {
    q.set("today", today);
    if (timeZone) q.set("tz", timeZone);
    return `?${q.toString()}`;
  };
  const monthHref = (y: number, m: number) => extra(new URLSearchParams({ m: `${y}-${String(m).padStart(2, "0")}` }));
  const yearHref = (y: number) => extra(new URLSearchParams({ view: "year", y: String(y) }));
  let prev: string;
  let next: string | null;
  let label: string;
  if (range.view === "month") {
    const pm = range.month === 1 ? [range.year - 1, 12] : [range.year, range.month - 1];
    const nm = range.month === 12 ? [range.year + 1, 1] : [range.year, range.month + 1];
    prev = monthHref(pm[0], pm[1]);
    next = nm[0] > ty || (nm[0] === ty && nm[1] > tm) ? null : monthHref(nm[0], nm[1]);
    label = `${MONTHS_LONG[range.month - 1]} ${range.year}`;
  } else {
    prev = yearHref(range.year - 1);
    next = range.year + 1 > ty ? null : yearHref(range.year + 1);
    label = String(range.year);
  }
  const tab = (active: boolean) =>
    cn(
      "inline-flex h-8 items-center gap-1 rounded-md px-3 text-sm font-medium transition",
      active ? "bg-card text-foreground shadow-sm" : "text-muted hover:text-foreground",
    );
  const arrow = "flex h-8 w-8 items-center justify-center rounded-lg border border-border bg-surface text-muted hover:bg-accent hover:text-foreground";
  return (
    <div className="flex flex-wrap items-center gap-2">
      <div className="inline-flex rounded-lg bg-accent p-0.5">
        <Link href={monthHref(range.view === "month" ? range.year : ty, range.view === "month" ? range.month : tm)} scroll={false} className={tab(range.view === "month")}>
          Bulan <LinkPending spinner={false} />
        </Link>
        <Link href={yearHref(range.year)} scroll={false} className={tab(range.view === "year")}>
          Tahun <LinkPending spinner={false} />
        </Link>
      </div>
      <div className="flex items-center gap-1">
        <Link href={prev} scroll={false} className={arrow} aria-label="Sebelumnya">
          <LinkPendingIcon>
            <ChevronLeft className="h-4 w-4" />
          </LinkPendingIcon>
        </Link>
        <span className="min-w-28 text-center text-sm font-semibold text-foreground">{label}</span>
        {next ? (
          <Link href={next} scroll={false} className={arrow} aria-label="Berikutnya">
            <LinkPendingIcon>
              <ChevronRight className="h-4 w-4" />
            </LinkPendingIcon>
          </Link>
        ) : (
          <span className={cn(arrow, "pointer-events-none opacity-40")} aria-hidden>
            <ChevronRight className="h-4 w-4" />
          </span>
        )}
      </div>
    </div>
  );
}

// ---------- Heatmap ----------

const STATUS_LABEL: Record<string, string> = {
  met: "Tercapai",
  partial: "Sebagian",
  skip: "Libur",
  missed: "Terlewat",
  pending: "Hari ini (belum)",
  off: "Bukan jadwal",
  before: "Sebelum mulai",
  future: "Belum terjadi",
  clean: "Bersih",
  relapse: "Kambuh",
};

function dayTitle(d: HeatmapDay, habit: HabitDetail["habit"], quit: boolean): string {
  const parts = [formatDay(d.date), STATUS_LABEL[d.status] ?? d.status];
  if (!quit && d.value != null && habit.target.type !== "check") parts.push(progressLabel(habit.target, d.value));
  if (d.relapses) parts.push(`${d.relapses}× kambuh`);
  if (d.urges) parts.push(`${d.urges}× tahan`);
  return parts.join(" · ");
}

function cellStyle(d: HeatmapDay, color: string): { className: string; style?: React.CSSProperties } {
  switch (d.status) {
    case "met":
    case "clean":
      return { className: "text-white", style: { background: color } };
    case "partial":
      return { className: "text-foreground", style: { background: `${color}66` } };
    case "skip":
      return { className: "bg-slate-300 text-slate-700" };
    case "missed":
      return { className: "bg-expense-soft text-expense" };
    case "relapse":
      return { className: "text-white", style: { background: RELAPSE_COLOR } };
    case "pending":
      return { className: "bg-surface text-foreground", style: { boxShadow: `inset 0 0 0 2px ${color}` } };
    case "off":
      return { className: "bg-accent text-muted-soft" };
    default:
      return { className: "bg-transparent text-muted-soft border border-dashed border-border" };
  }
}

function MonthHeatmap({
  days,
  color,
  today,
  quit,
  goalLabel,
}: {
  days: HeatmapDay[];
  color: string;
  today: string;
  quit: boolean;
  goalLabel: (d: HeatmapDay) => string;
}) {
  if (!days.length) return null;
  const lead = isoWeekday(days[0].date) - 1;
  return (
    <div className="mx-auto max-w-md">
      <div className="mb-1 grid grid-cols-7 gap-1.5 text-center text-[11px] font-medium text-muted">
        {WEEKDAYS_SHORT.map((w) => (
          <span key={w}>{w}</span>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1.5">
        {Array.from({ length: lead }, (_, i) => (
          <span key={`b${i}`} />
        ))}
        {days.map((d) => {
          const s = cellStyle(d, color);
          const title = goalLabel(d);
          return (
            <div
              key={d.date}
              title={title}
              aria-label={title}
              className={cn(
                "relative flex aspect-square items-center justify-center rounded-lg text-xs font-semibold tabular-nums",
                s.className,
                d.date === today && "ring-2 ring-foreground/40 ring-offset-1",
              )}
              style={s.style}
            >
              {Number(d.date.slice(8))}
              {quit && d.urges > 0 && (
                <span className="absolute bottom-0.5 right-0.5 rounded-full bg-amber-400 px-1 text-[9px] leading-tight text-white">
                  {d.urges}
                </span>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function YearHeatmap({
  days,
  color,
  today,
  goalLabel,
}: {
  days: HeatmapDay[];
  color: string;
  today: string;
  goalLabel: (d: HeatmapDay) => string;
}) {
  if (!days.length) return null;
  const lead = isoWeekday(days[0].date) - 1;
  const cells: (HeatmapDay | null)[] = [...Array.from({ length: lead }, () => null), ...days];
  const weeks: (HeatmapDay | null)[][] = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return (
    <div className="flex gap-1.5">
      <div className="flex shrink-0 flex-col gap-[3px] pt-4 text-[9px] leading-[11px] text-muted">
        {WEEKDAYS_SHORT.map((w, i) => (
          <span key={w} className="h-[11px]">
            {i % 2 === 0 ? w : ""}
          </span>
        ))}
      </div>
      <div className="overflow-x-auto pb-2">
        <div className="flex gap-[3px]">
          {weeks.map((w, wi) => {
            const monthStart = w.find((d) => d?.date.endsWith("-01"));
            const label = monthStart ? MONTHS_SHORT[Number(monthStart.date.slice(5, 7)) - 1] : "";
            return (
              <div key={wi} className="flex flex-col gap-[3px]">
                <span className="h-[13px] whitespace-nowrap text-[9px] leading-[13px] text-muted">{label}</span>
                {Array.from({ length: 7 }, (_, di) => {
                  const d = w[di];
                  if (!d) return <span key={di} className="h-[11px] w-[11px]" />;
                  const s = cellStyle(d, color);
                  const title = goalLabel(d);
                  return (
                    <span
                      key={di}
                      title={title}
                      aria-label={title}
                      className={cn("h-[11px] w-[11px] rounded-[2px]", s.className, d.date === today && "ring-1 ring-foreground")}
                      style={s.style}
                    />
                  );
                })}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function Legend({ color, quit }: { color: string; quit: boolean }) {
  const items: [string, HeatmapDay["status"]][] = quit
    ? [
        ["Bersih", "clean"],
        ["Kambuh", "relapse"],
        ["Sebelum mulai / nanti", "future"],
      ]
    : [
        ["Tercapai", "met"],
        ["Sebagian", "partial"],
        ["Terlewat", "missed"],
        ["Libur", "skip"],
        ["Bukan jadwal", "off"],
      ];
  return (
    <div className="mt-4 flex flex-wrap gap-x-4 gap-y-1.5 text-xs text-muted">
      {items.map(([label, status]) => {
        const s = cellStyle({ date: "", status, value: null, relapses: 0, urges: 0 }, color);
        return (
          <span key={label} className="inline-flex items-center gap-1.5">
            <span className={cn("h-3 w-3 rounded-[3px]", s.className)} style={s.style} />
            {label}
          </span>
        );
      })}
      {quit && (
        <span className="inline-flex items-center gap-1.5">
          <span className="rounded-full bg-amber-400 px-1 text-[9px] text-white">2</span> pengen, tapi tahan
        </span>
      )}
    </div>
  );
}

// ---------- Streak history ----------

function StreakHistory({ insights, color, quit, weekly }: { insights: HabitInsights; color: string; quit: boolean; weekly: boolean }) {
  const runs: { start: string; end: string; length: number; ongoing: boolean }[] = [];
  if (quit) {
    for (const s of insights.segments) runs.push({ start: s.start, end: s.end, length: s.days, ongoing: s.ongoing });
  } else if (weekly) {
    let cur: (typeof runs)[number] | null = null;
    for (const w of insights.weeks) {
      if (w.status === "met") {
        if (cur) {
          cur.length++;
          cur.end = w.week;
        } else cur = { start: w.week, end: w.week, length: 1, ongoing: false };
      } else if (w.status === "missed" && cur) {
        runs.push(cur);
        cur = null;
      }
    }
    if (cur) runs.push(cur);
  } else {
    let cur: (typeof runs)[number] | null = null;
    for (const d of insights.heatmap) {
      if (d.status === "met") {
        if (cur) {
          cur.length++;
          cur.end = d.date;
        } else cur = { start: d.date, end: d.date, length: 1, ongoing: false };
      } else if ((d.status === "missed" || d.status === "partial") && cur) {
        runs.push(cur);
        cur = null;
      }
    }
    if (cur) runs.push(cur);
  }
  const unit = weekly ? "minggu" : "hari";
  const data = runs.map((r) => {
    const [, m, d] = r.start.split("-").map(Number);
    return {
      label: `${d} ${MONTHS_SHORT[m - 1]}`,
      length: r.length,
      range: `${formatDay(r.start)} – ${formatDay(r.end)}`,
      ongoing: r.ongoing,
    };
  });
  return (
    <Card className="min-w-0">
      <CardHeader>
        <CardTitle>{quit ? "Riwayat hari bersih" : "Riwayat streak"}</CardTitle>
        <span className="text-xs text-muted">{runs.length} periode</span>
      </CardHeader>
      <CardContent>
        {data.length === 0 ? (
          <p className="py-8 text-center text-sm text-muted">Belum ada streak di rentang ini. Mulai dari hari ini 🌱</p>
        ) : (
          <StreakHistoryChart runs={data} color={color} unit={unit} />
        )}
      </CardContent>
    </Card>
  );
}

// ---------- Insights ----------

function QuitInsights({ insights }: { insights: HabitInsights }) {
  const r = insights.relapses;
  const u = insights.urges;
  const byWeekday = WEEKDAYS_SHORT.map((label, i) => ({ label, relapse: r.byWeekday[i], urge: u.byWeekday[i] }));
  const byHour = Array.from({ length: 24 }, (_, h) => ({ label: String(h).padStart(2, "0"), relapse: r.byHour[h], urge: u.byHour[h] }));
  const series = [
    { key: "relapse", label: "Kambuh", color: RELAPSE_COLOR },
    { key: "urge", label: "Pengen (tahan)", color: URGE_COLOR },
  ];
  const empty = r.total === 0 && u.total === 0;
  const maxTrig = insights.topTriggers[0]?.count ?? 0;
  const peakHour = byHour.reduce((best, x) => (x.relapse + x.urge > best.relapse + best.urge ? x : best), byHour[0]);
  const peakDay = byWeekday.reduce((best, x) => (x.relapse + x.urge > best.relapse + best.urge ? x : best), byWeekday[0]);
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card className="min-w-0">
        <CardHeader>
          <CardTitle>Per hari dalam minggu</CardTitle>
        </CardHeader>
        <CardContent>
          {empty ? (
            <EmptyInsight />
          ) : (
            <>
              <GroupedBars data={byWeekday} series={series} unit="×" />
              <p className="mt-2 text-xs text-muted">Paling sering: {dayLong(peakDay.label)}</p>
            </>
          )}
        </CardContent>
      </Card>
      <Card className="min-w-0">
        <CardHeader>
          <CardTitle>Per jam</CardTitle>
        </CardHeader>
        <CardContent>
          {empty ? (
            <EmptyInsight />
          ) : (
            <>
              <GroupedBars data={byHour} series={series} unit="×" interval={2} />
              <p className="mt-2 text-xs text-muted">
                Rawan sekitar jam {peakHour.label}.00
                {r.unknownHour + u.unknownHour > 0 && ` · ${r.unknownHour + u.unknownHour} catatan tanpa jam`}
              </p>
            </>
          )}
        </CardContent>
      </Card>
      <Card className="min-w-0 lg:col-span-2">
        <CardHeader>
          <CardTitle>Pemicu teratas</CardTitle>
          <span className="text-xs text-muted">{u.total}× berhasil tahan di rentang ini 💪</span>
        </CardHeader>
        <CardContent>
          {insights.topTriggers.length === 0 ? (
            <p className="py-4 text-center text-sm text-muted">Belum ada pemicu yang dicatat.</p>
          ) : (
            <ul className="space-y-2">
              {insights.topTriggers.slice(0, 8).map((t) => (
                <li key={t.tag} className="flex items-center gap-3 text-sm">
                  <span className="w-28 shrink-0 truncate font-medium text-foreground">{t.tag}</span>
                  <span className="h-2 flex-1 overflow-hidden rounded-full bg-accent">
                    <span className="block h-full rounded-full bg-amber-400" style={{ width: `${(t.count / maxTrig) * 100}%` }} />
                  </span>
                  <span className="w-8 shrink-0 text-right tabular-nums text-muted">{t.count}</span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

const dayLong = (short: string) =>
  ({ Sen: "Senin", Sel: "Selasa", Rab: "Rabu", Kam: "Kamis", Jum: "Jumat", Sab: "Sabtu", Min: "Minggu" })[short] ?? short;

function EmptyInsight() {
  return <p className="py-8 text-center text-sm text-muted">Belum ada catatan pengen/kambuh di rentang ini. Mantap 🌿</p>;
}

function BuildInsights({ insights, color }: { insights: HabitInsights; color: string }) {
  const met = Array(7).fill(0) as number[];
  const total = Array(7).fill(0) as number[];
  for (const d of insights.heatmap) {
    const i = isoWeekday(d.date) - 1;
    if (d.status === "met") {
      met[i]++;
      total[i]++;
    } else if (d.status === "missed" || d.status === "partial") total[i]++;
  }
  const data = WEEKDAYS_SHORT.map((label, i) => ({ label, rate: total[i] ? Math.round((met[i] / total[i]) * 100) : 0 }));
  const any = total.some((x) => x > 0);
  return (
    <Card className="min-w-0">
      <CardHeader>
        <CardTitle>Keberhasilan per hari</CardTitle>
      </CardHeader>
      <CardContent>
        {any ? (
          <GroupedBars data={data} series={[{ key: "rate", label: "Tercapai", color }]} unit="%" />
        ) : (
          <p className="py-8 text-center text-sm text-muted">Belum cukup data di rentang ini.</p>
        )}
      </CardContent>
    </Card>
  );
}

// ---------- Logs + journal ----------

function LogList({
  logs,
  habit,
  today,
  onChanged,
}: {
  logs: HabitLogDTO[];
  habit: HabitDetail["habit"];
  today: string;
  onChanged: () => void;
}) {
  const [journalOnly, setJournalOnly] = React.useState(false);
  const sorted = [...logs].sort((a, b) => (a.date === b.date ? a.type.localeCompare(b.type) : a.date < b.date ? 1 : -1));
  const shown = journalOnly ? sorted.filter((l) => l.note) : sorted;
  return (
    <Card className="min-w-0">
      <CardHeader className="flex-wrap gap-2">
        <CardTitle>Catatan & jurnal</CardTitle>
        <div className="inline-flex rounded-lg bg-accent p-0.5 text-sm">
          {[
            [false, "Semua"],
            [true, "Jurnal saja"],
          ].map(([v, label]) => (
            <button
              key={String(v)}
              type="button"
              onClick={() => setJournalOnly(v as boolean)}
              aria-pressed={journalOnly === v}
              className={cn(
                "h-8 rounded-md px-3 font-medium transition",
                journalOnly === v ? "bg-card text-foreground shadow-sm" : "text-muted hover:text-foreground",
              )}
            >
              {label as string}
            </button>
          ))}
        </div>
      </CardHeader>
      <CardContent>
        {shown.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted">
            {journalOnly ? "Belum ada jurnal di rentang ini." : "Belum ada catatan di rentang ini."}
          </p>
        ) : (
          <ul className="divide-y divide-border">
            {shown.map((l) => (
              <LogRow key={l.id} log={l} habit={habit} today={today} onChanged={onChanged} />
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

function LogRow({
  log,
  habit,
  today,
  onChanged,
}: {
  log: HabitLogDTO;
  habit: HabitDetail["habit"];
  today: string;
  onChanged: () => void;
}) {
  const [editing, setEditing] = React.useState(false);
  const [note, setNote] = React.useState(log.note ?? "");
  const [confirm, setConfirm] = React.useState(false);
  const [pending, startTransition] = React.useTransition();
  const [busy, setBusy] = React.useState<"note" | "delete" | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  function run(kind: "note" | "delete", fn: () => Promise<{ ok: boolean; error?: string }>) {
    setError(null);
    setBusy(kind);
    startTransition(async () => {
      try {
        const res = await fn();
        if (!res.ok) setError(res.error ?? "Terjadi kesalahan");
        else {
          setEditing(false);
          setConfirm(false);
          onChanged();
        }
      } catch {
        setError("Gagal menyimpan, periksa koneksi");
      }
    });
  }

  const value =
    log.type === "done"
      ? habit.kind === "quit"
        ? "Hari bersih ✅"
        : progressLabel(habit.target, log.value)
      : log.type === "relapse" || log.type === "urge"
        ? `${fmtNum(log.value ?? 1)}×`
        : "";
  const time = log.at && (log.type === "relapse" || log.type === "urge") ? new Date(log.at).toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" }) : null;
  const tone =
    log.type === "relapse" ? "bg-expense-soft text-expense" : log.type === "urge" ? "bg-amber-100 text-amber-700" : log.type === "skip" ? "bg-accent text-muted" : "bg-income-soft text-income";

  return (
    <li className={cn("py-3 first:pt-0 last:pb-0", pending && "opacity-70")}>
      <div className="flex flex-wrap items-center gap-2">
        <span className="w-24 shrink-0 text-sm font-medium text-foreground" suppressHydrationWarning>
          {formatDay(log.date, today)}
        </span>
        <span className={cn("rounded-full px-2 py-0.5 text-xs font-semibold", tone)}>{LOG_TYPE_LABEL[log.type] ?? log.type}</span>
        {value && <span className="text-sm tabular-nums text-foreground">{value}</span>}
        {time && (
          <span className="text-xs text-muted" suppressHydrationWarning>
            {time}
          </span>
        )}
        <div className="ml-auto flex items-center gap-1">
          {!editing && (
            <Button variant="ghost" size="sm" onClick={() => setEditing(true)} disabled={pending}>
              <Pencil className="h-3.5 w-3.5" /> {log.note ? "Ubah jurnal" : "Tulis jurnal"}
            </Button>
          )}
          {confirm ? (
            <>
              <Button variant="danger" size="sm" loading={pending && busy === "delete"} onClick={() => run("delete", () => deleteHabitLog(log.id))}>
                Hapus
              </Button>
              <Button variant="ghost" size="sm" onClick={() => setConfirm(false)} disabled={pending}>
                Batal
              </Button>
            </>
          ) : (
            <Button variant="ghost" size="icon" className="h-8 w-8 text-muted hover:text-expense" aria-label="Hapus catatan ini" onClick={() => setConfirm(true)} disabled={pending}>
              <Trash2 className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>
      {log.triggers.length > 0 && (
        <div className="mt-1.5 flex flex-wrap gap-1">
          {log.triggers.map((t) => (
            <span key={t} className="rounded-full bg-accent px-2 py-0.5 text-[11px] font-medium text-muted">
              {t}
            </span>
          ))}
        </div>
      )}
      {editing ? (
        <form
          className="mt-2 space-y-2"
          onSubmit={(e) => {
            e.preventDefault();
            run("note", () => setHabitLogNote(habit.id, log.date, log.type as HabitLogType, note.trim() || null));
          }}
        >
          <Textarea
            value={note}
            maxLength={HABIT_NOTE_MAX}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Apa yang kamu rasakan hari itu?"
            autoFocus
            aria-label="Jurnal"
          />
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              disabled={pending}
              onClick={() => {
                setEditing(false);
                setNote(log.note ?? "");
              }}
            >
              Batal
            </Button>
            <Button type="submit" size="sm" loading={pending && busy === "note"}>
              Simpan jurnal
            </Button>
          </div>
        </form>
      ) : (
        log.note && <p className="mt-1.5 whitespace-pre-line text-sm text-foreground">{log.note}</p>
      )}
      <ErrorLine error={error} className="mt-1" />
    </li>
  );
}
