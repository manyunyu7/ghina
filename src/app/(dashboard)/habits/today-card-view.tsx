"use client";

import * as React from "react";
import Link from "next/link";
import { ArrowRight, Check, Lock, Plus } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { LinkPendingIcon } from "@/components/link-pending";
import { cn } from "@/lib/utils";
import type { HabitTarget } from "@/lib/habits";
import { checkInHabit, uncheckHabit } from "./actions";
import { ProgressRing } from "./parts";
import { fmtNum } from "./format";

export type TodayRow = {
  id: string;
  /** Already masked for private habits. */
  name: string;
  emoji: string | null;
  private: boolean;
  color: string;
  kind: "build" | "quit";
  target: HabitTarget;
  today: {
    progress: number | null;
    met: boolean;
    skipped: boolean;
    cleanCheckIn: boolean;
    streak: number;
    unit: "day" | "week";
    relapsedToday: boolean;
    beforeStart: boolean;
  };
};

export function HabitsTodayCardView({ rows, more, today }: { rows: TodayRow[]; more: number; today: string }) {
  const build = rows.filter((r) => r.kind === "build" && !r.today.skipped);
  const met = build.filter((r) => r.today.met).length;
  return (
    <Card>
      <CardHeader>
        <CardTitle>🌱 Kebiasaan hari ini</CardTitle>
        <Link href="/habits" className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline">
          Buka Kebiasaan{" "}
          <LinkPendingIcon className="h-3.5 w-3.5">
            <ArrowRight className="h-3.5 w-3.5" />
          </LinkPendingIcon>
        </Link>
      </CardHeader>
      <CardContent>
        {build.length > 0 && (
          <p className="-mt-2 mb-3 text-xs text-muted">
            {met}/{build.length} tercapai{met === build.length ? " 🎉" : ""}
          </p>
        )}
        <ul className="grid gap-x-6 gap-y-2 sm:grid-cols-2">
          {rows.map((r) => (
            <Row key={r.id} row={r} today={today} />
          ))}
        </ul>
        {more > 0 && <p className="pt-2 text-xs text-muted">+{more} lainnya</p>}
      </CardContent>
    </Card>
  );
}

function Row({ row, today }: { row: TodayRow; today: string }) {
  const [pending, startTransition] = React.useTransition();
  const [error, setError] = React.useState<string | null>(null);
  const t = row.today;
  const run = (fn: () => Promise<{ ok: boolean; error?: string }>) => {
    setError(null);
    startTransition(async () => {
      try {
        const res = await fn();
        if (!res.ok) setError(res.error ?? "Gagal");
      } catch {
        setError("Gagal menyimpan");
      }
    });
  };

  let status: React.ReactNode;
  let action: React.ReactNode = null;
  if (row.kind === "quit") {
    status = t.relapsedToday ? "Mulai lagi besok 🌱" : `🔥 Hari bersih ke-${t.streak}`;
    if (!t.relapsedToday && !t.beforeStart)
      action = (
        <CheckButton
          done={t.cleanCheckIn}
          color="#16a34a"
          pending={pending}
          label={t.cleanCheckIn ? "Batalkan hari ini bersih" : "Tandai hari ini bersih"}
          onClick={() => run(() => (t.cleanCheckIn ? uncheckHabit(row.id, today) : checkInHabit(row.id, { date: today })))}
        />
      );
  } else if (t.skipped) {
    status = "Libur hari ini";
  } else if (row.target.type === "check") {
    status = t.met ? `Selesai · 🔥 ${t.streak}` : `🔥 ${t.streak} ${t.unit === "week" ? "minggu" : "hari"}`;
    action = (
      <CheckButton
        done={t.met}
        color={row.color}
        pending={pending}
        label={t.met ? "Batalkan selesai" : "Tandai selesai"}
        onClick={() => run(() => (t.met ? uncheckHabit(row.id, today) : checkInHabit(row.id, { date: today })))}
      />
    );
  } else {
    const p = t.progress ?? 0;
    const goal = row.target.goal;
    const unit = row.target.type === "count" ? row.target.unit : "mnt";
    status = `${fmtNum(p)}/${fmtNum(goal)} ${unit}`.trim() + (t.met ? " ✓" : "");
    action =
      row.target.type === "count" ? (
        <button
          type="button"
          onClick={() => run(() => checkInHabit(row.id, { date: today, add: 1 }))}
          disabled={pending}
          aria-label={`Tambah 1 ${row.name}`}
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border-2 transition hover:bg-accent disabled:opacity-50"
          style={{ borderColor: row.color, color: row.color }}
        >
          {pending ? <Spinner /> : <Plus className="h-4 w-4" strokeWidth={3} />}
        </button>
      ) : (
        <ProgressRing value={p / goal} color={row.color} size={32} stroke={4} label={status as string} />
      );
  }

  return (
    <li className="flex items-center gap-3 py-1">
      <span
        aria-hidden
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-base"
        style={{ background: `${row.color}22`, color: row.color }}
      >
        {row.private ? <Lock className="h-3.5 w-3.5" /> : row.emoji || row.name.charAt(0).toUpperCase()}
      </span>
      <div className="min-w-0 flex-1">
        <p className={cn("truncate text-sm font-medium", row.private ? "italic text-muted" : "text-foreground")}>{row.name}</p>
        <p className={cn("truncate text-xs", error ? "text-expense" : "text-muted")}>{error ?? status}</p>
      </div>
      {action}
    </li>
  );
}

function CheckButton({
  done,
  color,
  pending,
  label,
  onClick,
}: {
  done: boolean;
  color: string;
  pending: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={pending}
      aria-pressed={done}
      aria-label={label}
      className={cn(
        "flex h-8 w-8 shrink-0 items-center justify-center rounded-full border-2 transition disabled:opacity-50",
        done ? "border-transparent text-white" : "hover:bg-accent",
      )}
      style={done ? { background: color } : { borderColor: color, color }}
    >
      {pending ? <Spinner /> : <Check className="h-4 w-4" strokeWidth={3} />}
    </button>
  );
}

function Spinner() {
  return <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-t-transparent" />;
}
