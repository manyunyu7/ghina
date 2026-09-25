"use client";

import * as React from "react";
import Link from "next/link";
import { Bell, Check, ChevronRight, Lock, Minus, Moon, Pencil, Plus, RotateCcw } from "lucide-react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { LinkPendingIcon } from "@/components/link-pending";
import { cn } from "@/lib/utils";
import { MAX_SKIPS_PER_7_DAYS, nextQuitMilestone, type HabitToday } from "@/lib/habits";
import type { HabitOverviewItem } from "@/lib/habits-server";
import type { ActionResult } from "@/lib/action-utils";
import { checkInHabit, logUrge, setHabitSkip, uncheckHabit } from "./actions";
import { ErrorLine, HabitAvatar, ProgressRing } from "./parts";
import { fmtNum, formatDay, progressLabel, scheduleLabel } from "./format";
import { RelapseDialog } from "./relapse-dialog";
import { UrgeDialog, type UrgeLogState } from "./urge-dialog";

type Busy = "check" | "plus" | "minus" | "add" | "reset" | "skip" | "clean" | null;

/** One habit on the Today board (also used at the top of the detail page). */
export function HabitCard({
  item,
  today,
  canSkipToday,
  blur = false,
  onEdit,
  detailLink = true,
  refreshAfter = false,
}: {
  item: HabitOverviewItem;
  today: string;
  canSkipToday: boolean;
  blur?: boolean;
  onEdit?: () => void;
  detailLink?: boolean;
  /** Refresh the route after actions (pages the actions don't revalidate, e.g. the detail page). */
  refreshAfter?: boolean;
}) {
  const router = useRouter();
  const [pending, startTransition] = React.useTransition();
  const [busy, setBusy] = React.useState<Busy>(null);
  const [error, setError] = React.useState<string | null>(null);
  const t = item.today;
  const quit = item.kind === "quit";

  function run(key: Busy, fn: () => Promise<ActionResult<{ today?: HabitToday }>>) {
    setError(null);
    setBusy(key);
    startTransition(async () => {
      try {
        const res = await fn();
        if (!res.ok) setError(res.error);
        else if (refreshAfter) router.refresh();
      } catch {
        setError("Gagal menyimpan, periksa koneksi");
      }
    });
  }
  const isBusy = (k: Busy) => pending && busy === k;

  // ---- urge / relapse dialogs (quit) ----
  const [urgeOpen, setUrgeOpen] = React.useState(false);
  const [urgeLog, setUrgeLog] = React.useState<UrgeLogState>({ pending: false, error: null, urgesToday: null });
  const [relapseOpen, setRelapseOpen] = React.useState(false);

  function startUrge() {
    setUrgeOpen(true);
    setUrgeLog({ pending: true, error: null, urgesToday: null });
    (async () => {
      try {
        const res = await logUrge(item.id, { date: today, at: new Date().toISOString() });
        setUrgeLog(res.ok ? { pending: false, error: null, urgesToday: res.urgesToday } : { pending: false, error: res.error, urgesToday: null });
      } catch {
        setUrgeLog({ pending: false, error: "Gagal mencatat, periksa koneksi", urgesToday: null });
      }
    })();
  }

  const closeDialogs = () => {
    setUrgeOpen(false);
    setRelapseOpen(false);
    if (refreshAfter) router.refresh();
  };

  const nameCls = cn("truncate text-base font-semibold text-foreground transition", blur && "select-none blur-[6px] hover:blur-none");
  const inactive = !quit && !t.scheduled && !t.met;
  const beforeStart = item.startDate > today;

  return (
    <div
      className={cn(
        "flex flex-col gap-3 rounded-card border border-border bg-card p-4 shadow-sm transition",
        inactive && "bg-surface/60",
        pending && "opacity-90",
      )}
      style={{ borderTopColor: item.color, borderTopWidth: 3 }}
    >
      {/* Header */}
      <div className="flex items-start gap-3">
        <HabitAvatar emoji={item.emoji} name={item.name} color={item.color} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            {detailLink ? (
              <Link href={`/habits/${item.id}`} className={cn(nameCls, "hover:text-primary")}>
                {item.name}
              </Link>
            ) : (
              <span className={nameCls}>{item.name}</span>
            )}
            {item.private && <Lock className="h-3.5 w-3.5 shrink-0 text-muted" aria-label="Pribadi" />}
          </div>
          <p className="flex flex-wrap items-center gap-x-2 text-xs text-muted">
            <span>{quit ? "Berhenti" : scheduleLabel(item.schedule)}</span>
            {item.reminders.length > 0 && (
              <span className="inline-flex items-center gap-0.5" title="Pengingat (dikirim dari aplikasi HP)">
                <Bell className="h-3 w-3" /> {item.reminders.join(", ")}
              </span>
            )}
          </p>
        </div>
        {onEdit && (
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={onEdit} aria-label={`Ubah ${item.name}`}>
            <Pencil className="h-4 w-4" />
          </Button>
        )}
        {detailLink && (
          <Link
            href={`/habits/${item.id}`}
            aria-label={`Detail ${item.name}`}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-muted hover:bg-accent hover:text-foreground"
          >
            <LinkPendingIcon>
              <ChevronRight className="h-4 w-4" />
            </LinkPendingIcon>
          </Link>
        )}
      </div>

      {beforeStart ? (
        <p className="rounded-lg bg-accent/70 px-3 py-2 text-sm text-muted">Mulai {formatDay(item.startDate, today)} 🌱</p>
      ) : quit ? (
        <QuitBody
          t={t}
          color={item.color}
          isBusy={isBusy}
          disabled={pending}
          onClean={() => run("clean", () => (t.cleanCheckIn ? uncheckHabit(item.id, today) : checkInHabit(item.id, { date: today })))}
          onUrge={startUrge}
          onRelapse={() => setRelapseOpen(true)}
        />
      ) : (
        <BuildBody
          item={item}
          today={today}
          canSkipToday={canSkipToday}
          isBusy={isBusy}
          disabled={pending}
          run={run}
        />
      )}

      <ErrorLine error={error} />

      {quit && (
        <>
          <UrgeDialog
            open={urgeOpen}
            onClose={closeDialogs}
            habitId={item.id}
            habitName={item.name}
            why={item.why}
            color={item.color}
            today={today}
            current={t.streak.current}
            log={urgeLog}
            onRetry={startUrge}
          />
          <RelapseDialog
            open={relapseOpen}
            onClose={closeDialogs}
            habitId={item.id}
            habitName={item.name}
            color={item.color}
            today={today}
            current={t.streak.current}
          />
        </>
      )}
    </div>
  );
}

function QuitBody({
  t,
  color,
  isBusy,
  disabled,
  onClean,
  onUrge,
  onRelapse,
}: {
  t: HabitToday;
  color: string;
  isBusy: (k: Busy) => boolean;
  disabled: boolean;
  onClean: () => void;
  onUrge: () => void;
  onRelapse: () => void;
}) {
  const s = t.streak;
  const days = s.current;
  const next = nextQuitMilestone(days);
  const relapsed = s.kind === "quit" && s.relapsedToday;
  return (
    <>
      <div className="flex items-center gap-4">
        <ProgressRing value={days / next} color={color} size={76} stroke={7} label={`${days} dari ${next} hari`}>
          <span className="text-2xl font-bold tabular-nums text-foreground">{days}</span>
          <span className="text-[10px] text-muted">hari</span>
        </ProgressRing>
        <div className="min-w-0">
          {relapsed ? (
            <>
              <p className="text-base font-semibold text-foreground">Mulai lagi besok 🌱</p>
              <p className="text-xs text-muted">Hari ini tercatat kambuh. Itu data, bukan kegagalan.</p>
            </>
          ) : (
            <>
              <p className="text-base font-semibold text-foreground">Hari bersih ke-{days}</p>
              <p className="text-xs text-muted">hari ini masih berjalan · target berikutnya {next} hari</p>
            </>
          )}
          <p className="mt-1 text-xs text-muted">
            Terlama {s.longest} hari
            {t.urges > 0 && ` · ${t.urges}× tahan hari ini 💪`}
          </p>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <Button
          variant={t.cleanCheckIn ? "primary" : "outline"}
          className={cn("col-span-2", t.cleanCheckIn && "bg-income hover:bg-green-700")}
          onClick={onClean}
          loading={isBusy("clean")}
          disabled={disabled || relapsed}
          aria-pressed={t.cleanCheckIn}
        >
          {!isBusy("clean") && <Check className="h-4 w-4" />}
          {t.cleanCheckIn ? "Hari ini bersih ✅" : "Tandai hari ini bersih"}
        </Button>
        <Button variant="secondary" onClick={onUrge} disabled={disabled} className="font-semibold" style={{ color }}>
          Lagi pengen…
        </Button>
        <Button variant="ghost" onClick={onRelapse} disabled={disabled} className="text-muted">
          Aku kalah
        </Button>
      </div>
    </>
  );
}

function BuildBody({
  item,
  today,
  canSkipToday,
  isBusy,
  disabled,
  run,
}: {
  item: HabitOverviewItem;
  today: string;
  canSkipToday: boolean;
  isBusy: (k: Busy) => boolean;
  disabled: boolean;
  run: (key: Busy, fn: () => Promise<ActionResult<{ today?: HabitToday }>>) => void;
}) {
  const t = item.today;
  const target = item.target;
  const s = t.streak;
  const unit = s.unit === "week" ? "minggu" : "hari";
  const progress = t.progress ?? 0;
  const [minutes, setMinutes] = React.useState("");

  const streakLine = (
    <p className="text-xs text-muted">
      🔥 <b className="text-foreground">{s.current}</b> {unit} beruntun · terlama {s.longest}
    </p>
  );

  if (t.skipped)
    return (
      <div className="flex items-center justify-between gap-3 rounded-lg bg-accent/70 px-3 py-2">
        <div>
          <p className="flex items-center gap-1.5 text-sm font-medium text-foreground">
            <Moon className="h-4 w-4" /> Libur hari ini
          </p>
          {streakLine}
        </div>
        <Button
          variant="ghost"
          size="sm"
          loading={isBusy("skip")}
          disabled={disabled}
          onClick={() => run("skip", () => setHabitSkip(item.id, today, false))}
        >
          Batal libur
        </Button>
      </div>
    );

  if (!t.scheduled && !t.met && item.schedule.type !== "perWeek")
    return (
      <div className="rounded-lg bg-accent/70 px-3 py-2">
        <p className="text-sm text-muted">Bukan jadwal hari ini — santai dulu ☕</p>
        {streakLine}
      </div>
    );

  const skipButton = !t.met && (
    <Button
      variant="ghost"
      size="sm"
      className="text-muted"
      loading={isBusy("skip")}
      disabled={disabled || !canSkipToday}
      title={canSkipToday ? "Libur tidak memutus streak" : `Maksimal ${MAX_SKIPS_PER_7_DAYS} hari libur dalam 7 hari`}
      onClick={() => run("skip", () => setHabitSkip(item.id, today, true))}
    >
      <Moon className="h-4 w-4" /> Libur hari ini
    </Button>
  );
  const skipHint = !t.met && !canSkipToday && (
    <p className="text-[11px] text-muted">Jatah libur habis (maks {MAX_SKIPS_PER_7_DAYS}× per 7 hari).</p>
  );
  const weekNote =
    item.schedule.type === "perWeek" && !t.scheduled && !t.met ? (
      <p className="text-xs font-medium text-income">Target minggu ini sudah tercapai 🎉</p>
    ) : null;

  if (target.type === "check")
    return (
      <>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => run("check", () => (t.met ? uncheckHabit(item.id, today) : checkInHabit(item.id, { date: today })))}
            disabled={disabled}
            aria-pressed={t.met}
            aria-label={t.met ? "Batalkan selesai hari ini" : "Tandai selesai hari ini"}
            className={cn(
              "flex h-14 w-14 shrink-0 items-center justify-center rounded-full border-[3px] transition active:scale-95 disabled:opacity-60",
              t.met ? "border-transparent text-white" : "border-border text-muted-soft hover:border-current",
            )}
            style={t.met ? { background: item.color } : { color: item.color }}
          >
            {isBusy("check") ? (
              <span className="h-5 w-5 animate-spin rounded-full border-2 border-current border-t-transparent" />
            ) : (
              <Check className="h-7 w-7" strokeWidth={3} />
            )}
          </button>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-semibold text-foreground">{t.met ? "Selesai hari ini 🎉" : "Belum hari ini"}</p>
            {streakLine}
            {weekNote}
          </div>
        </div>
        {(skipButton || skipHint) && (
          <div className="-mt-1 flex flex-col items-start">
            {skipButton}
            {skipHint}
          </div>
        )}
      </>
    );

  const goal = target.goal;
  const addMinutes = (n: number) => run("add", () => checkInHabit(item.id, { date: today, add: n }));

  return (
    <>
      <div className="flex items-center gap-3">
        <ProgressRing value={progress / goal} color={item.color} size={64} label={progressLabel(target, progress)}>
          {t.met ? (
            <Check className="h-6 w-6" style={{ color: item.color }} strokeWidth={3} />
          ) : (
            <span className="text-sm font-bold tabular-nums text-foreground">{Math.round((progress / goal) * 100)}%</span>
          )}
        </ProgressRing>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold tabular-nums text-foreground">
            {progressLabel(target, progress)}
            {t.met && " 🎉"}
          </p>
          {streakLine}
          {weekNote}
        </div>
      </div>

      {target.type === "count" ? (
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="icon"
            aria-label="Kurangi 1"
            loading={isBusy("minus")}
            disabled={disabled || progress <= 0}
            onClick={() =>
              run("minus", () =>
                progress - 1 <= 0 ? uncheckHabit(item.id, today) : checkInHabit(item.id, { date: today, value: progress - 1 }),
              )
            }
          >
            <Minus className="h-4 w-4" />
          </Button>
          <Button
            className="flex-1"
            loading={isBusy("plus")}
            disabled={disabled}
            onClick={() => run("plus", () => checkInHabit(item.id, { date: today, add: 1 }))}
            style={{ background: item.color }}
          >
            {!isBusy("plus") && <Plus className="h-4 w-4" />} 1 {target.unit}
          </Button>
        </div>
      ) : (
        <div className="space-y-2">
          <div className="flex flex-wrap items-center gap-2">
            {[5, 15, 30].map((n) => (
              <Button key={n} variant="outline" size="sm" disabled={disabled} onClick={() => addMinutes(n)}>
                +{n} mnt
              </Button>
            ))}
            {progress > 0 && (
              <Button
                variant="ghost"
                size="sm"
                className="text-muted"
                loading={isBusy("reset")}
                disabled={disabled}
                onClick={() => run("reset", () => uncheckHabit(item.id, today))}
                aria-label="Reset progres hari ini"
              >
                {!isBusy("reset") && <RotateCcw className="h-3.5 w-3.5" />} Reset
              </Button>
            )}
          </div>
          <form
            className="flex items-center gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              const n = Math.round(Number(minutes));
              if (!Number.isFinite(n) || n <= 0) return;
              setMinutes("");
              addMinutes(n);
            }}
          >
            <Input
              type="number"
              inputMode="numeric"
              min={1}
              max={1440}
              value={minutes}
              onChange={(e) => setMinutes(e.target.value)}
              placeholder="Menit"
              aria-label="Tambah menit"
              className="h-8 w-24"
            />
            <Button type="submit" size="sm" loading={isBusy("add")} disabled={disabled || !minutes} style={{ background: item.color }}>
              Tambah
            </Button>
            <span className="text-xs text-muted">dari {fmtNum(goal)} mnt</span>
          </form>
        </div>
      )}
      {(skipButton || skipHint) && (
        <div className="-mt-1 flex flex-col items-start">
          {skipButton}
          {skipHint}
        </div>
      )}
    </>
  );
}
