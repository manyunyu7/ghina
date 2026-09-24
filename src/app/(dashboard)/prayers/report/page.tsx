import Link from "next/link";
import { ArrowLeft, Gauge, CalendarCheck, Sparkles, Moon } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge, PageHeader } from "@/components/ui/misc";
import { cn } from "@/lib/utils";
import {
  STATUSES,
  SUNNAH,
  UNFILLED,
  RAWATIB_PER_DAY,
  computeReport,
  prayerLabel,
  type CountKey,
} from "@/lib/prayer-quality";
import { todayKey } from "../constants";
import { PRAYER_SELECT, formatLong, toDTO } from "../types";
import { RangePicker } from "./range-picker";
import { ColorMap } from "./color-map";
import { resolveRange } from "./range";

type SearchParams = { preset?: string; from?: string; to?: string };

export default async function PrayerReportPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const user = await requireUser();
  const sp = await searchParams;
  const today = todayKey();
  const range = resolveRange(sp, today);

  const rows = await prisma.prayerEntry.findMany({
    where: { userId: user.id, date: { gte: range.from, lte: range.to } },
    select: PRAYER_SELECT,
  });
  const entries = rows.map(toDTO);
  const r = computeReport(entries, range.from, range.to, today);

  const pctRows: { key: CountKey | "jamaahAll"; label: string; color: string; count: number }[] = [
    { key: "jamaahAll", label: "Jamaah (masjid + jamaah)", color: STATUSES[1].color, count: r.counts.masjid + r.counts.jamaah },
    ...STATUSES.filter((s) => s.id !== "excused").map((s) => ({ key: s.id, label: s.label, color: s.color, count: r.counts[s.id] })),
    { key: "unfilled", label: UNFILLED.label, color: UNFILLED.color, count: r.counts.unfilled },
  ];

  const scoreTone =
    r.score == null ? "text-muted" : r.score >= 75 ? "text-income" : r.score >= 50 ? "text-amber-500" : "text-expense";

  return (
    <div>
      <PageHeader
        title="Laporan Shalat"
        description={`${formatLong(range.from)} – ${formatLong(range.to)}`}
        action={
          <Link href="/prayers" className="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline">
            <ArrowLeft className="h-4 w-4" /> Kembali ke pencatatan
          </Link>
        }
      />

      <RangePicker preset={range.preset} from={range.from} to={range.to} today={today} />

      {/* Summary */}
      <div className="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Tile icon={<Gauge className="h-5 w-5" />} tint="bg-primary-soft text-primary" label="Skor kualitas">
          <span className={cn("text-3xl font-bold tabular-nums", scoreTone)}>{r.score ?? "–"}</span>
          <span className="text-sm text-muted"> / 100</span>
          <p className="mt-1 text-xs text-muted">
            {r.points} poin dari {r.counted} waktu shalat
          </p>
        </Tile>
        <Tile icon={<CalendarCheck className="h-5 w-5" />} tint="bg-income-soft text-income" label="Hari lengkap (5/5)">
          <span className="text-3xl font-bold tabular-nums text-foreground">{r.completeDays}</span>
          <span className="text-sm text-muted"> / {r.daysElapsed} hari</span>
          {r.neutralDays > 0 && <p className="mt-1 text-xs text-muted">{r.neutralDays} hari berhalangan (netral)</p>}
        </Tile>
        <Tile icon={<Sparkles className="h-5 w-5" />} tint="bg-amber-100 text-amber-600" label="Rawatib">
          <span className="text-3xl font-bold tabular-nums text-foreground">{r.rawatib.total}</span>
          <span className="text-sm text-muted"> / {r.daysElapsed * RAWATIB_PER_DAY}</span>
          <p className="mt-1 text-xs text-muted">
            {r.rawatib.qobliyah} qobliyah · {r.rawatib.badiyah} ba&apos;diyah
          </p>
        </Tile>
        <Tile icon={<Moon className="h-5 w-5" />} tint="bg-indigo-100 text-indigo-600" label="Sunnah harian">
          <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1">
            {SUNNAH.map((s) => (
              <span key={s.id} className="inline-flex items-center gap-1.5 text-sm">
                <span className="h-2.5 w-2.5 rounded-full" style={{ background: s.color }} />
                <span className="text-muted">{s.label}</span>
                <span className="font-semibold tabular-nums text-foreground">{r.sunnah[s.id]}×</span>
              </span>
            ))}
          </div>
        </Tile>
      </div>

      {/* Color map */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Peta warna</CardTitle>
        </CardHeader>
        <CardContent>
          <ColorMap from={range.from} to={range.to} today={today} entries={entries} />
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Percentages */}
        <Card>
          <CardHeader>
            <CardTitle>Persentase</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {pctRows.map((row) => {
              const pct = r.pct[row.key];
              return (
                <div key={row.key}>
                  <div className="mb-1 flex items-center justify-between text-sm">
                    <span className="inline-flex items-center gap-2 text-foreground">
                      <span className="h-2.5 w-2.5 rounded-sm" style={{ background: row.color }} />
                      {row.label}
                    </span>
                    <span className="tabular-nums text-muted">
                      {pct}% <span className="text-muted-soft">({row.count})</span>
                    </span>
                  </div>
                  <div className="h-2 overflow-hidden rounded-full bg-accent">
                    <div className="h-full rounded-full" style={{ width: `${pct}%`, background: row.color }} />
                  </div>
                </div>
              );
            })}
            <p className="pt-1 text-xs text-muted">
              Dihitung dari {r.counted} waktu shalat. Berhalangan ({r.counts.excused}) tidak dihitung.
            </p>
          </CardContent>
        </Card>

        {/* Per-prayer breakdown */}
        <Card>
          <CardHeader>
            <CardTitle>Per waktu shalat</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {r.perPrayer.map((b) => {
              const total = b.counted + b.counts.excused;
              const segments: { key: string; color: string; n: number; label: string }[] = [
                ...STATUSES.map((s) => ({ key: s.id, color: s.color, n: b.counts[s.id], label: s.label })),
                { key: "unfilled", color: UNFILLED.color, n: b.counts.unfilled, label: UNFILLED.label },
              ];
              const isWeak = r.weakest === b.prayer;
              const isStrong = r.strongest === b.prayer;
              return (
                <div
                  key={b.prayer}
                  className={cn(
                    "rounded-xl p-2",
                    isWeak && "bg-expense-soft/60 ring-1 ring-expense/30",
                    isStrong && "bg-income-soft/60 ring-1 ring-income/30",
                  )}
                >
                  <div className="mb-1.5 flex items-center justify-between gap-2 text-sm">
                    <span className="flex items-center gap-2 font-semibold text-foreground">
                      {prayerLabel(b.prayer)}
                      {isStrong && <Badge variant="income">Terkuat</Badge>}
                      {isWeak && <Badge variant="expense">Terlemah</Badge>}
                    </span>
                    <span className="tabular-nums text-muted">
                      skor <span className="font-semibold text-foreground">{b.score ?? "–"}</span>
                    </span>
                  </div>
                  <div className="flex h-3 overflow-hidden rounded-full bg-accent">
                    {total > 0 &&
                      segments
                        .filter((s) => s.n > 0)
                        .map((s) => (
                          <div
                            key={s.key}
                            title={`${s.label}: ${s.n}`}
                            style={{ width: `${(s.n / total) * 100}%`, background: s.color }}
                          />
                        ))}
                  </div>
                  <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-muted">
                    {segments
                      .filter((s) => s.n > 0)
                      .map((s) => (
                        <span key={s.key} className="inline-flex items-center gap-1">
                          <span className="h-2 w-2 rounded-sm" style={{ background: s.color }} />
                          {s.label.split(" (")[0]} {s.n}
                        </span>
                      ))}
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function Tile({
  icon,
  tint,
  label,
  children,
}: {
  icon: React.ReactNode;
  tint: string;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <Card className="p-4">
      <div className={`mb-3 flex h-9 w-9 items-center justify-center rounded-lg ${tint}`}>{icon}</div>
      <p className="text-sm text-muted">{label}</p>
      <div>{children}</div>
    </Card>
  );
}
