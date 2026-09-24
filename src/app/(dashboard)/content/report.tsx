"use client";

import * as React from "react";
import { AlertTriangle, BarChart3, Eye, Flame, Heart, Loader2, Send, Trophy } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { EmptyState } from "@/components/ui/misc";
import { FORMATS, localParts, type BestPost, type ContentReport, type GroupStat, type SponsorSummary } from "@/lib/content";
import { addDaysKey, daysInMonth } from "@/lib/tasks";
import { cn, formatCompactCurrency, formatCurrency } from "@/lib/utils";
import { fetchContentReport } from "./actions";
import { usePlanner } from "./planner";
import { AverageBars, MonthBars, type AvgPoint } from "./report-charts";
import {
  AccountAvatar,
  AccountCode,
  formatCompact,
  formatDateKey,
  formatMonthKey,
  formatNumber,
  formatPercent,
  handleText,
  pillarColor,
  Segmented,
  WEEKDAYS_LONG,
  WEEKDAYS_SHORT,
} from "./ui";
import { platformLabel } from "@/lib/content";
import type { SocialAccountDTO } from "./types";

type Preset = "7" | "30" | "bulan" | "bulanlalu" | "90" | "tahun" | "kustom";
const PRESETS: { id: Preset; label: string }[] = [
  { id: "7", label: "7 hari" },
  { id: "30", label: "30 hari" },
  { id: "bulan", label: "Bulan ini" },
  { id: "bulanlalu", label: "Bulan lalu" },
  { id: "90", label: "90 hari" },
  { id: "tahun", label: "Tahun ini" },
  { id: "kustom", label: "Kustom" },
];
const pad = (n: number) => String(n).padStart(2, "0");

function presetRange(p: Preset, today: string): { from: string; to: string } | null {
  const [y, m] = today.split("-").map(Number);
  switch (p) {
    case "7":
      return { from: addDaysKey(today, -6), to: today };
    case "30":
      return { from: addDaysKey(today, -29), to: today };
    case "90":
      return { from: addDaysKey(today, -89), to: today };
    case "bulan":
      return { from: `${y}-${pad(m)}-01`, to: today };
    case "bulanlalu": {
      const py = m === 1 ? y - 1 : y;
      const pm = m === 1 ? 12 : m - 1;
      return { from: `${py}-${pad(pm)}-01`, to: `${py}-${pad(pm)}-${pad(daysInMonth(py, pm))}` };
    }
    case "tahun":
      return { from: `${y}-01-01`, to: today };
    default:
      return null;
  }
}

type ReportData = { report: ContentReport; sponsors: SponsorSummary; accounts: SocialAccountDTO[] };
type Group = "pilar" | "format" | "hari" | "jam";
type Metric = "views" | "engagement" | "rate";

export function ContentReportView() {
  const { data, tz, version } = usePlanner();
  const today = localParts(new Date(), tz).date;
  const [preset, setPreset] = React.useState<Preset>("30");
  const [custom, setCustom] = React.useState(() => ({ from: addDaysKey(today, -29), to: today }));
  const range = presetRange(preset, today) ?? custom;
  const [res, setRes] = React.useState<{ key: string; data: ReportData } | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const key = `${range.from}|${range.to}|${tz}|${version}`;
  const valid = range.from <= range.to;

  React.useEffect(() => {
    if (!valid) return;
    let alive = true;
    fetchContentReport({ from: range.from, to: range.to, timeZone: tz })
      .then((r) => {
        if (!alive) return;
        if (r.ok) {
          setRes({ key, data: { report: r.report, sponsors: r.sponsors, accounts: r.accounts } });
          setError(null);
        } else setError(r.error);
      })
      .catch(() => alive && setError("Gagal memuat laporan"));
    return () => {
      alive = false;
    };
  }, [key, range.from, range.to, tz, valid, data.posts]);

  const loading = !res || res.key !== key;
  const rd = res?.data;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <div className="-mx-4 max-w-[calc(100%+2rem)] overflow-x-auto px-4 sm:mx-0 sm:max-w-full sm:px-0">
          <Segmented label="Rentang laporan" value={preset} onChange={setPreset} options={PRESETS} className="[&_button]:whitespace-nowrap" />
        </div>
        {preset === "kustom" && (
          <div className="flex items-center gap-2">
            <Input type="date" aria-label="Dari tanggal" value={custom.from} max={custom.to} onChange={(e) => e.target.value && setCustom((c) => ({ ...c, from: e.target.value }))} className="h-9 w-40" />
            <span className="text-muted">–</span>
            <Input type="date" aria-label="Sampai tanggal" value={custom.to} min={custom.from} onChange={(e) => e.target.value && setCustom((c) => ({ ...c, to: e.target.value }))} className="h-9 w-40" />
          </div>
        )}
        <span className="text-sm text-muted">
          {formatDateKey(range.from)} – {formatDateKey(range.to)}
        </span>
        {loading && valid && <Loader2 className="h-4 w-4 animate-spin text-muted" aria-label="Memuat" />}
      </div>

      {!valid && <p className="text-sm text-expense">Tanggal awal harus sebelum tanggal akhir.</p>}
      {error && (
        <p role="alert" className="rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          {error}
        </p>
      )}

      {rd ? (
        <ReportBody rd={rd} dim={loading} />
      ) : (
        valid &&
        !error && (
          <div className="animate-pulse space-y-4" aria-busy="true" aria-label="Memuat laporan">
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              {[0, 1, 2, 3].map((i) => (
                <div key={i} className="h-24 rounded-card border border-border bg-card" />
              ))}
            </div>
            <div className="h-72 rounded-card border border-border bg-card" />
          </div>
        )
      )}
    </div>
  );
}

function ReportBody({ rd, dim }: { rd: ReportData; dim: boolean }) {
  const { data, openItem } = usePlanner();
  const { report, sponsors } = rd;
  const accById = new Map(rd.accounts.map((a) => [a.id, a]));
  const cur = data.currency;

  if (rd.accounts.length === 0 && report.totals.posted === 0) {
    return (
      <EmptyState
        icon={BarChart3}
        title="Belum ada data laporan"
        description="Tambah akun dulu di Pengaturan, jadwalkan posting, lalu tandai “Sudah tayang”. Laporan konsistensi dan performa muncul di sini."
      />
    );
  }

  const accountRows = report.accounts.filter((a) => {
    const acc = accById.get(a.accountId);
    return acc && (!acc.archived || a.posted > 0);
  });

  return (
    <div className={cn("space-y-4 transition-opacity", dim && "opacity-60")}>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat icon={Send} label="Tayang" value={formatNumber(report.totals.posted)} sub={`${report.totals.scheduled} terjadwal · ${report.totals.skipped} dilewati`} />
        <Stat icon={Eye} label="Tayangan" value={formatCompact(report.totals.views)} sub={report.totals.posted ? `rata-rata ${formatCompact(report.totals.views / report.totals.posted)}/posting` : undefined} />
        <Stat icon={Heart} label="Engagement" value={formatCompact(report.totals.engagement)} sub={report.totals.views ? `rate ${formatPercent(report.totals.engagement / report.totals.views)}` : undefined} />
        <Stat icon={Trophy} label="Minggu penuh" value={String(report.weeks.length)} sub={`${report.days} hari dalam rentang`} />
      </div>

      {/* Per account vs target + consistency */}
      <Card>
        <CardHeader>
          <CardTitle>Konsistensi per akun</CardTitle>
        </CardHeader>
        <CardContent>
          {accountRows.length === 0 ? (
            <p className="text-sm text-muted">Tambah akun dulu di Pengaturan.</p>
          ) : (
            <ul className="divide-y divide-border">
              {accountRows.map((a) => {
                const acc = accById.get(a.accountId)!;
                const pct = a.ratio != null ? Math.min(100, a.ratio * 100) : 0;
                return (
                  <li key={a.accountId} className="flex flex-wrap items-center gap-3 py-3 first:pt-0 last:pb-0">
                    <AccountAvatar account={acc} />
                    <div className="min-w-[160px] flex-1">
                      <p className="truncate text-sm font-medium text-foreground">
                        {platformLabel(acc)} <span className="font-normal text-muted">{handleText(acc.handle)}</span>
                        {acc.archived && <span className="ml-1 text-xs text-muted-soft">(diarsipkan)</span>}
                      </p>
                      {a.expected != null ? (
                        <>
                          <div className="mt-1 h-2 overflow-hidden rounded-full bg-accent">
                            <div className="h-full rounded-full" style={{ width: `${pct}%`, background: acc.color }} />
                          </div>
                          <p className="mt-1 text-xs text-muted">
                            <b className="text-foreground">{a.posted}</b> dari target {a.expected} ({a.target}/minggu, disesuaikan rentang)
                          </p>
                        </>
                      ) : (
                        <p className="mt-1 text-xs text-muted">
                          <b className="text-foreground">{a.posted}</b> tayang · tanpa target mingguan
                        </p>
                      )}
                    </div>
                    {a.target != null && (
                      <div className="flex gap-4 text-center text-xs">
                        <div>
                          <p className="flex items-center justify-center gap-0.5 text-base font-bold text-foreground">
                            <Flame className={cn("h-4 w-4", a.currentStreak ? "text-orange-500" : "text-muted-soft")} aria-hidden />
                            {a.currentStreak}
                          </p>
                          <p className="text-muted">streak kini</p>
                        </div>
                        <div>
                          <p className="text-base font-bold text-foreground">{a.longestStreak}</p>
                          <p className="text-muted">terpanjang</p>
                        </div>
                        <div>
                          <p className="text-base font-bold text-foreground">
                            {a.weeksMet}/{a.weeks}
                          </p>
                          <p className="text-muted">minggu tercapai</p>
                        </div>
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
          {report.weeks.length === 0 && <p className="mt-3 text-xs text-muted-soft">Streak dihitung dari minggu penuh (Sen–Min) di dalam rentang.</p>}
        </CardContent>
      </Card>

      {/* Best posts */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <BestList title="Terbaik: tayangan" rows={report.bestByViews} accById={accById} kind="views" onOpen={(id) => openItem({ mode: "edit", id })} />
        <BestList title="Terbaik: engagement" rows={report.bestByEngagement} accById={accById} kind="engagement" onOpen={(id) => openItem({ mode: "edit", id })} />
      </div>

      <Averages report={report} />

      <PillarBalance balance={report.pillarBalance} />

      <SponsorCard sponsors={sponsors} range={{ from: report.from, to: report.to }} accById={accById} currency={cur} onOpen={(id) => openItem({ mode: "edit", id })} />
    </div>
  );
}

function Stat({ icon: Icon, label, value, sub }: { icon: React.ComponentType<{ className?: string }>; label: string; value: string; sub?: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="flex items-center gap-1.5 text-sm text-muted">
          <Icon className="h-4 w-4" /> {label}
        </p>
        <p className="mt-1 text-2xl font-bold tracking-tight text-foreground">{value}</p>
        {sub && <p className="mt-0.5 truncate text-xs text-muted">{sub}</p>}
      </CardContent>
    </Card>
  );
}

function BestList({
  title,
  rows,
  accById,
  kind,
  onOpen,
}: {
  title: string;
  rows: BestPost[];
  accById: Map<string, SocialAccountDTO>;
  kind: "views" | "engagement";
  onOpen: (contentId: string) => void;
}) {
  return (
    <Card className="min-w-0">
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>
        {rows.length === 0 ? (
          <p className="text-sm text-muted">Belum ada data performa. Isi performa posting yang sudah tayang (tayangan, suka, komentar…).</p>
        ) : (
          <ol className="space-y-2">
            {rows.map((r, i) => {
              const a = accById.get(r.accountId);
              return (
                <li key={r.postId}>
                  <button type="button" onClick={() => onOpen(r.contentId)} className="flex w-full items-center gap-2 rounded-lg p-1 text-left hover:bg-accent">
                    <span className="w-5 shrink-0 text-center text-sm font-bold text-muted">{i + 1}</span>
                    {a && <AccountCode account={a} />}
                    <span className="min-w-0 flex-1 truncate text-sm text-foreground">{r.title || "Tanpa judul"}</span>
                    <span className="shrink-0 text-right text-sm font-semibold tabular-nums text-foreground">
                      {kind === "views" ? formatCompact(r.views ?? 0) : formatCompact(r.engagement)}
                      <span className="block text-[11px] font-normal text-muted">
                        {kind === "views" ? `${formatCompact(r.engagement)} eng.` : r.rate != null ? `rate ${formatPercent(r.rate)}` : "—"}
                      </span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}

function Averages({ report }: { report: ContentReport }) {
  const [group, setGroup] = React.useState<Group>("pilar");
  const [metric, setMetric] = React.useState<Metric>("views");
  const stats: GroupStat[] = { pilar: report.byPillar, format: report.byFormat, hari: report.byWeekday, jam: report.byHour }[group];
  const byKey = new Map(stats.map((s) => [s.key, s]));
  const keys =
    group === "hari" ? ["1", "2", "3", "4", "5", "6", "7"] : group === "jam" ? Array.from({ length: 24 }, (_, h) => String(h)) : stats.map((s) => s.key);
  const label = (k: string) =>
    group === "hari"
      ? WEEKDAYS_SHORT[Number(k) - 1]
      : group === "jam"
        ? `${pad(Number(k))}`
        : group === "format"
          ? (FORMATS.find((f) => f.id === k)?.label ?? "Tanpa format")
          : k || "Tanpa pilar";
  const value = (s: GroupStat | undefined) => (!s ? null : metric === "views" ? s.avgViews : metric === "engagement" ? s.avgEngagement : s.avgRate);
  const points: AvgPoint[] = keys.map((k) => {
    const s = byKey.get(k);
    return { label: label(k), value: value(s), posts: s?.posts ?? 0, withMetrics: s?.withMetrics ?? 0 };
  });
  const fmt = metric === "rate" ? formatPercent : formatCompact;
  const metricLabel = metric === "views" ? "Rata-rata tayangan" : metric === "engagement" ? "Rata-rata engagement" : "Rata-rata engagement rate";
  const any = points.some((p) => p.value != null);
  const best = [...points].filter((p) => p.value != null).sort((a, b) => b.value! - a.value!)[0];
  const bestLabel = best && (group === "hari" ? WEEKDAYS_LONG[WEEKDAYS_SHORT.indexOf(best.label)] : group === "jam" ? `jam ${best.label}.00` : best.label);

  return (
    <Card className="min-w-0">
      <CardHeader className="flex-wrap gap-2">
        <CardTitle>Rata-rata performa</CardTitle>
        <div className="flex flex-wrap gap-2">
          <Segmented
            label="Kelompok"
            value={group}
            onChange={setGroup}
            options={[
              { id: "pilar", label: "Pilar" },
              { id: "format", label: "Format" },
              { id: "hari", label: "Hari" },
              { id: "jam", label: "Jam" },
            ]}
            className="[&_button]:px-2 [&_button]:py-1 [&_button]:text-xs"
          />
          <Segmented
            label="Metrik"
            value={metric}
            onChange={setMetric}
            options={[
              { id: "views", label: "Tayangan" },
              { id: "engagement", label: "Engagement" },
              { id: "rate", label: "Rate" },
            ]}
            className="[&_button]:px-2 [&_button]:py-1 [&_button]:text-xs"
          />
        </div>
      </CardHeader>
      <CardContent>
        {!any ? (
          <p className="py-8 text-center text-sm text-muted">Belum ada posting dengan data performa di rentang ini.</p>
        ) : (
          <>
            {best && (
              <p className="mb-2 text-sm text-muted">
                Tertinggi: <b className="text-foreground">{bestLabel}</b> ({fmt(best.value!)})
              </p>
            )}
            <AverageBars data={points} format={fmt} metricLabel={metricLabel} />
            <p className="mt-2 text-xs text-muted-soft">Rata-rata dari posting tayang yang sudah diisi performanya; waktu mengikuti zona waktu perangkatmu.</p>
          </>
        )}
      </CardContent>
    </Card>
  );
}

function PillarBalance({ balance }: { balance: ContentReport["pillarBalance"] }) {
  const { data } = usePlanner();
  const total = balance.reduce((s, b) => s + b.count, 0);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Keseimbangan pilar</CardTitle>
      </CardHeader>
      <CardContent>
        {total === 0 ? (
          <p className="text-sm text-muted">Belum ada posting tayang di rentang ini.</p>
        ) : (
          <>
            <div className="flex h-4 w-full gap-0.5 overflow-hidden rounded-full" role="img" aria-label="Porsi posting per pilar">
              {balance.map((b) => (
                <div key={b.key || "-"} style={{ width: `${b.share * 100}%`, background: pillarColor(data.pillars, b.key || null) }} title={`${b.key || "Tanpa pilar"}: ${formatPercent(b.share)}`} />
              ))}
            </div>
            <ul className="mt-3 grid grid-cols-1 gap-x-6 gap-y-1.5 sm:grid-cols-2">
              {balance.map((b) => (
                <li key={b.key || "-"} className="flex items-center gap-2 text-sm">
                  <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: pillarColor(data.pillars, b.key || null) }} />
                  <span className="min-w-0 flex-1 truncate text-foreground">{b.key || "Tanpa pilar"}</span>
                  <span className="tabular-nums text-muted">
                    {b.count} · <b className="text-foreground">{formatPercent(b.share)}</b>
                  </span>
                </li>
              ))}
            </ul>
          </>
        )}
      </CardContent>
    </Card>
  );
}

function SponsorCard({
  sponsors,
  range,
  accById,
  currency,
  onOpen,
}: {
  sponsors: SponsorSummary;
  range: { from: string; to: string };
  accById: Map<string, SocialAccountDTO>;
  currency: string;
  onOpen: (id: string) => void;
}) {
  const months = sponsors.byMonth.filter((m) => m.month >= range.from.slice(0, 7) && m.month <= range.to.slice(0, 7));
  const inRange = months.reduce((s, m) => s + m.amount, 0);
  const fmt = (v: number) => formatCurrency(v, currency);
  const none = sponsors.byMonth.length === 0 && sponsors.unpaid.length === 0;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Pendapatan sponsor</CardTitle>
        {!none && <span className="text-sm font-semibold text-income">{fmt(inRange)}</span>}
      </CardHeader>
      <CardContent className="space-y-5">
        {none ? (
          <p className="text-sm text-muted">Belum ada konten bersponsor. Tandai konten sebagai endorse di detail konten untuk melacak pembayarannya.</p>
        ) : (
          <>
            <div>
              <p className="mb-1 text-xs font-medium text-muted">Per bulan (lunas, dalam rentang)</p>
              {months.length ? (
                <MonthBars data={months.map((m) => ({ label: formatMonthKey(m.month), amount: m.amount, count: m.count }))} format={(v) => formatCompactCurrency(v, currency)} />
              ) : (
                <p className="text-sm text-muted">Tidak ada sponsor lunas di rentang ini.</p>
              )}
            </div>
            <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
              <div>
                <p className="mb-2 text-xs font-medium text-muted">Per akun (semua waktu, dibagi rata antar akun konten)</p>
                {sponsors.byAccount.length === 0 ? (
                  <p className="text-sm text-muted">—</p>
                ) : (
                  <ul className="space-y-1.5">
                    {sponsors.byAccount.map((b) => {
                      const a = accById.get(b.accountId);
                      return (
                        <li key={b.accountId || "-"} className="flex items-center gap-2 text-sm">
                          {a ? <AccountCode account={a} /> : <span className="w-6" />}
                          <span className="min-w-0 flex-1 truncate text-foreground">{a ? handleText(a.handle) : "Tanpa akun"}</span>
                          <span className="font-semibold tabular-nums text-foreground">{fmt(b.amount)}</span>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </div>
              <div>
                <p className="mb-2 text-xs font-medium text-muted">Belum dibayar</p>
                {sponsors.unpaid.length === 0 ? (
                  <p className="text-sm text-muted">Semua sponsor sudah lunas 👍</p>
                ) : (
                  <ul className="space-y-1.5">
                    {sponsors.unpaid.map((u) => (
                      <li key={u.contentId}>
                        <button type="button" onClick={() => onOpen(u.contentId)} className="flex w-full items-center gap-2 rounded-lg p-1 text-left text-sm hover:bg-accent">
                          {u.overdue && <AlertTriangle className="h-4 w-4 shrink-0 text-expense" aria-label="Lewat jatuh tempo" />}
                          <span className="min-w-0 flex-1 truncate">
                            <span className="font-medium text-foreground">{u.brand}</span> <span className="text-muted">· {u.title}</span>
                          </span>
                          <span className="shrink-0 text-right tabular-nums">
                            <span className="block font-semibold text-foreground">{u.amount ? formatCurrency(u.amount, u.currency) : "Barter"}</span>
                            <span className={cn("block text-[11px]", u.overdue ? "text-expense" : "text-muted")}>{u.due ? formatDateKey(u.due) : "tanpa tempo"}</span>
                          </span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
