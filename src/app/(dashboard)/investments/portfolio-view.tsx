"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Archive, ArchiveRestore, ChevronDown, CircleAlert, Pencil, Plus, RefreshCw, TrendingUp } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge, EmptyState, PageHeader } from "@/components/ui/misc";
import { Money } from "@/components/money/money";
import { BalanceToggle } from "@/components/money/balance-privacy";
import { PendingBar } from "@/components/pending-bar";
import { assetKindInfo } from "@/lib/investments";
import type { Portfolio } from "@/lib/investments-server";
import { cn } from "@/lib/utils";
import { fetchPortfolio, setAssetArchived } from "./actions";
import { AllocationCard, HistoryCard } from "./charts";
import { AssetFormDialog } from "./asset-form";
import { TradeFormDialog } from "./trade-form";
import { ManualPriceDialog } from "./dialogs";
import { fmtDate, fmtDateTime, fmtPct, fmtPrice, plTone, qtyLabel } from "./format";
import type { AssetDTO, HistoryPoint, HoldingRow, WalletOption } from "./types";

export function PortfolioView({
  portfolio,
  archived,
  wallets,
  history,
  currency,
}: {
  portfolio: Portfolio;
  archived: HoldingRow[];
  wallets: WalletOption[];
  history: HistoryPoint[];
  currency: string;
}) {
  const router = useRouter();
  const { summary, holdings, pricesAsOf } = portfolio;
  const [adding, setAdding] = React.useState(false);
  const [tradeFor, setTradeFor] = React.useState<HoldingRow | null>(null);
  const [priceFor, setPriceFor] = React.useState<AssetDTO | null>(null);
  const [refreshing, startRefresh] = React.useTransition();
  const [refreshMsg, setRefreshMsg] = React.useState<string | null>(null);

  const refreshPrices = React.useCallback(() => {
    setRefreshMsg(null);
    startRefresh(async () => {
      const r = await fetchPortfolio({ refresh: true });
      if (!r.ok) setRefreshMsg(r.error);
      else if (r.portfolio.summary.staleCount > 0) setRefreshMsg("Sebagian harga belum bisa diperbarui — memakai harga terakhir.");
      startRefresh(() => router.refresh());
    });
  }, [router]);

  // First paint uses cached prices; refresh stale ones once in the background.
  const autoRefreshed = React.useRef(false);
  const needsRefresh = holdings.some((h) => h.asset.priceMode === "auto" && h.holding.shares > 0 && (h.quote?.stale ?? true));
  React.useEffect(() => {
    if (autoRefreshed.current || !needsRefresh) return;
    autoRefreshed.current = true;
    startRefresh(async () => {
      const r = await fetchPortfolio({ refresh: true });
      if (r.ok) startRefresh(() => router.refresh());
    });
  }, [needsRefresh, router]);

  const hasAuto = holdings.some((h) => h.asset.priceMode === "auto");

  if (holdings.length === 0 && archived.length === 0) {
    return (
      <div>
        <PageHeader title="Investasi" description="Pantau saham, reksa dana, emas, dan aset lain Anda." />
        <EmptyState
          icon={TrendingUp}
          title="Belum ada aset"
          description="Tambahkan saham (mis. BBCA), reksa dana, emas, atau kripto. Kepemilikan dihitung dari transaksi beli/jual yang Anda catat."
          action={
            <Button onClick={() => setAdding(true)}>
              <Plus className="h-4 w-4" /> Tambah aset pertama
            </Button>
          }
        />
        <AssetFormDialog open={adding} onClose={() => setAdding(false)} wallets={wallets} />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PendingBar pending={refreshing} label="Memperbarui harga…" />
      <PageHeader
        title="Investasi"
        description="Nilai portofolio mengikuti harga pasar dan dihitung dari transaksi Anda."
        action={
          <div className="flex flex-wrap gap-2">
            {hasAuto && (
              <Button variant="outline" onClick={refreshPrices} loading={refreshing}>
                {!refreshing && <RefreshCw className="h-4 w-4" />}
                {refreshing ? "Memperbarui…" : "Perbarui harga"}
              </Button>
            )}
            <Button onClick={() => setAdding(true)}>
              <Plus className="h-4 w-4" /> Tambah aset
            </Button>
          </div>
        }
      />

      {/* Summary */}
      <section className="grid gap-4 lg:grid-cols-3" aria-label="Ringkasan portofolio" data-testid="portfolio-summary">
        <div className="rounded-card bg-primary p-5 text-white shadow-sm">
          <div className="flex items-center gap-1">
            <p className="text-sm font-medium text-white/80">Nilai pasar</p>
            <BalanceToggle className="-my-1 p-1 text-white/80 hover:bg-white/15 hover:text-white" />
          </div>
          <p className="mt-1 text-3xl font-bold tracking-tight" data-testid="market-value">
            <Money amount={summary.marketValue} currency={currency} />
          </p>
          {hasAuto && (
            <p className="mt-2 text-sm text-white/90">
              Hari ini{" "}
              <span className="font-semibold">
                <Money amount={summary.dayChange} currency={currency} sign="auto" />
              </span>
            </p>
          )}
          <PriceStatus asOf={pricesAsOf} stale={summary.staleCount} unpriced={summary.unpricedCount} hasAuto={hasAuto} />
        </div>
        <div className="grid grid-cols-2 gap-3 lg:col-span-2 lg:grid-cols-3">
          <Stat label="Modal" value={<Money amount={summary.cost} currency={currency} />} />
          <Stat
            label="Belum terealisasi"
            tone={summary.unrealized}
            testId="unrealized"
            value={<Money amount={summary.unrealized} currency={currency} sign="auto" />}
            sub={fmtPct(summary.unrealizedPct)}
          />
          <Stat label="Perubahan hari ini" tone={summary.dayChange} value={<Money amount={summary.dayChange} currency={currency} sign="auto" />} />
          <Stat label="Terealisasi" tone={summary.realized} testId="realized" value={<Money amount={summary.realized} currency={currency} sign="auto" />} />
          <Stat label="Dividen" testId="dividends" value={<Money amount={summary.dividends} currency={currency} />} />
          <Stat
            label="Total imbal hasil"
            tone={summary.totalReturn}
            testId="total-return"
            value={<Money amount={summary.totalReturn} currency={currency} sign="auto" />}
          />
        </div>
      </section>
      {refreshMsg && (
        <p className="-mt-3 flex items-center gap-1.5 text-sm text-amber-600" role="status">
          <CircleAlert className="h-4 w-4" /> {refreshMsg}
        </p>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <AllocationCard byAsset={summary.byAsset} byKind={summary.byKind} currency={currency} />
        <HistoryCard history={history} currency={currency} />
      </div>

      {/* Holdings */}
      <section aria-label="Kepemilikan">
        <h2 className="mb-3 text-base font-semibold text-foreground">Kepemilikan</h2>
        {holdings.length === 0 ? (
          <p className="rounded-card border border-dashed border-border p-6 text-center text-sm text-muted">Semua aset diarsipkan.</p>
        ) : (
          <HoldingsList rows={holdings} onTrade={setTradeFor} onPrice={setPriceFor} />
        )}
      </section>

      {archived.length > 0 && <ArchivedSection rows={archived} />}

      <AssetFormDialog open={adding} onClose={() => setAdding(false)} wallets={wallets} />
      {tradeFor && (
        <TradeFormDialog
          open
          onClose={() => setTradeFor(null)}
          asset={tradeFor.asset}
          holding={tradeFor.holding}
          lastPrice={tradeFor.valuation.price}
          wallets={wallets}
        />
      )}
      {priceFor && <ManualPriceDialog open asset={priceFor} onClose={() => setPriceFor(null)} />}
    </div>
  );
}

function PriceStatus({ asOf, stale, unpriced, hasAuto }: { asOf: string | null; stale: number; unpriced: number; hasAuto: boolean }) {
  return (
    <div className="mt-3 flex flex-wrap items-center gap-1.5 text-xs text-white/80" data-testid="price-status">
      {hasAuto && <span>{asOf ? `Harga per ${fmtDateTime(asOf)}` : "Harga pasar belum tersedia"}</span>}
      {stale > 0 && <span className="rounded-full bg-amber-400/90 px-2 py-0.5 font-medium text-amber-950">{stale} harga usang</span>}
      {unpriced > 0 && (
        <span className="rounded-full bg-white/20 px-2 py-0.5 font-medium" title="Aset tanpa harga dihitung sebesar modalnya">
          {unpriced} tanpa harga (pakai modal)
        </span>
      )}
    </div>
  );
}

function Stat({ label, value, sub, tone, testId }: { label: string; value: React.ReactNode; sub?: string; tone?: number; testId?: string }) {
  return (
    <div className="min-w-0 rounded-card border border-border bg-card p-4 shadow-sm" data-testid={testId}>
      <p className="truncate text-xs text-muted">{label}</p>
      <p className={cn("mt-1 truncate text-lg font-bold tracking-tight", tone === undefined ? "text-foreground" : plTone(tone))}>{value}</p>
      {sub && <p className={cn("text-xs font-medium", plTone(tone))}>{sub}</p>}
    </div>
  );
}

/** "harga manual per 25 Sep 2026" / day change for auto prices. */
function PriceLine({ row }: { row: HoldingRow }) {
  const { asset, valuation, priceSource, quote } = row;
  if (priceSource === "manual")
    return <span className="text-xs text-muted">harga manual per {asset.manualPriceAt ? fmtDate(asset.manualPriceAt) : "–"}</span>;
  if (priceSource === "auto")
    return (
      <span className="inline-flex flex-wrap items-center gap-1 text-xs">
        <span className={plTone(valuation.dayChangePct)}>{fmtPct(valuation.dayChangePct)}</span>
        {quote?.stale && <span className="rounded-full bg-amber-100 px-1.5 text-[10px] font-medium text-amber-800">usang</span>}
      </span>
    );
  return <span className="text-xs text-muted">{asset.priceMode === "auto" ? "harga belum tersedia" : "belum ada harga"}</span>;
}

function HoldingsList({ rows, onTrade, onPrice }: { rows: HoldingRow[]; onTrade: (r: HoldingRow) => void; onPrice: (a: AssetDTO) => void }) {
  return (
    <>
      {/* md+: table */}
      <div className="hidden overflow-x-auto rounded-card border border-border bg-card shadow-sm md:block">
        <table className="w-full text-sm" data-testid="holdings-table">
          <thead>
            <tr className="border-b border-border text-left text-xs text-muted">
              <th className="px-4 py-3 font-medium">Aset</th>
              <th className="px-3 py-3 text-right font-medium">Jumlah</th>
              <th className="px-3 py-3 text-right font-medium">Rata-rata</th>
              <th className="px-3 py-3 text-right font-medium">Harga</th>
              <th className="px-3 py-3 text-right font-medium">Nilai pasar</th>
              <th className="px-3 py-3 text-right font-medium">Laba/rugi</th>
              <th className="w-24 px-3 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {rows.map((r) => {
              const q = qtyLabel(r.asset, r.holding.shares);
              return (
                <tr key={r.asset.id} className="transition hover:bg-accent/40" data-testid={`holding-${r.asset.symbol}`}>
                  <td className="px-4 py-3">
                    <AssetCell row={r} />
                  </td>
                  <td className="px-3 py-3 text-right">
                    <div className="font-medium text-foreground">{q.main}</div>
                    {q.sub && <div className="text-xs text-muted">{q.sub}</div>}
                  </td>
                  <td className="px-3 py-3 text-right text-foreground">
                    {r.holding.avgPrice != null ? <Money amount={r.holding.avgPrice} currency={r.asset.currency} /> : "–"}
                  </td>
                  <td className="px-3 py-3 text-right">
                    <div className="font-medium text-foreground">{r.valuation.price != null ? fmtPrice(r.valuation.price, r.asset.currency) : "–"}</div>
                    <PriceLine row={r} />
                  </td>
                  <td className="px-3 py-3 text-right font-semibold text-foreground">
                    <Money amount={r.value} currency={r.asset.currency} />
                  </td>
                  <td className={cn("px-3 py-3 text-right", plTone(r.valuation.unrealized))}>
                    {r.valuation.unrealized != null ? (
                      <>
                        <div className="font-semibold">
                          <Money amount={r.valuation.unrealized} currency={r.asset.currency} sign="auto" />
                        </div>
                        <div className="text-xs">{fmtPct(r.valuation.unrealizedPct)}</div>
                      </>
                    ) : (
                      <span className="text-muted">–</span>
                    )}
                  </td>
                  <td className="px-3 py-3">
                    <RowActions row={r} onTrade={onTrade} onPrice={onPrice} />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* < md: cards */}
      <ul className="space-y-3 md:hidden" data-testid="holdings-cards">
        {rows.map((r) => {
          const q = qtyLabel(r.asset, r.holding.shares);
          return (
            <li key={r.asset.id} className="rounded-card border border-border bg-card p-4 shadow-sm">
              <div className="flex items-start justify-between gap-3">
                <AssetCell row={r} />
                <div className="shrink-0 text-right">
                  <div className="font-semibold text-foreground">
                    <Money amount={r.value} currency={r.asset.currency} />
                  </div>
                  {r.valuation.unrealized != null && (
                    <div className={cn("text-xs font-medium", plTone(r.valuation.unrealized))}>
                      <Money amount={r.valuation.unrealized} currency={r.asset.currency} sign="auto" /> ({fmtPct(r.valuation.unrealizedPct)})
                    </div>
                  )}
                </div>
              </div>
              <div className="mt-3 grid grid-cols-3 gap-2 text-xs">
                <div>
                  <p className="text-muted">Jumlah</p>
                  <p className="font-medium text-foreground">{q.main}</p>
                  {q.sub && <p className="text-muted">{q.sub}</p>}
                </div>
                <div>
                  <p className="text-muted">Rata-rata</p>
                  <p className="font-medium text-foreground">
                    {r.holding.avgPrice != null ? <Money amount={r.holding.avgPrice} currency={r.asset.currency} /> : "–"}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-muted">Harga</p>
                  <p className="font-medium text-foreground">{r.valuation.price != null ? fmtPrice(r.valuation.price, r.asset.currency) : "–"}</p>
                  <PriceLine row={r} />
                </div>
              </div>
              <div className="mt-3 flex justify-end border-t border-border pt-2">
                <RowActions row={r} onTrade={onTrade} onPrice={onPrice} />
              </div>
            </li>
          );
        })}
      </ul>
    </>
  );
}

function AssetCell({ row }: { row: HoldingRow }) {
  const { asset } = row;
  return (
    <Link href={`/investments/${asset.id}`} className="group flex min-w-0 items-center gap-3">
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary-soft text-[11px] font-bold text-primary">
        {asset.symbol.slice(0, 4)}
      </span>
      <span className="min-w-0">
        <span className="block truncate font-semibold text-foreground group-hover:text-primary group-hover:underline">{asset.symbol}</span>
        <span className="block truncate text-xs text-muted">{asset.name || assetKindInfo(asset.kind).label}</span>
      </span>
    </Link>
  );
}

function RowActions({ row, onTrade, onPrice }: { row: HoldingRow; onTrade: (r: HoldingRow) => void; onPrice: (a: AssetDTO) => void }) {
  return (
    <div className="flex items-center justify-end gap-1">
      {row.asset.priceMode === "manual" && (
        <Button variant="ghost" size="sm" onClick={() => onPrice(row.asset)} aria-label={`Perbarui harga ${row.asset.symbol}`} title="Perbarui harga manual">
          <Pencil className="h-3.5 w-3.5" />
          <span className="md:hidden">Harga</span>
        </Button>
      )}
      <Button variant="ghost" size="sm" onClick={() => onTrade(row)} aria-label={`Transaksi ${row.asset.symbol}`} title="Catat transaksi">
        <Plus className="h-3.5 w-3.5" />
        <span className="md:hidden">Transaksi</span>
      </Button>
    </div>
  );
}

function ArchivedSection({ rows }: { rows: HoldingRow[] }) {
  const [open, setOpen] = React.useState(false);
  return (
    <section aria-label="Aset diarsipkan">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="flex items-center gap-2 text-sm font-semibold text-muted transition hover:text-foreground"
      >
        <Archive className="h-4 w-4" /> Diarsipkan ({rows.length})
        <ChevronDown className={cn("h-4 w-4 transition", open && "rotate-180")} />
      </button>
      {open && (
        <ul className="mt-3 divide-y divide-border rounded-card border border-border bg-card">
          {rows.map((r) => (
            <ArchivedRow key={r.asset.id} row={r} />
          ))}
        </ul>
      )}
    </section>
  );
}

function ArchivedRow({ row }: { row: HoldingRow }) {
  const [pending, startTransition] = React.useTransition();
  const [error, setError] = React.useState<string | null>(null);
  return (
    <li className="flex items-center gap-3 p-3">
      <div className="min-w-0 flex-1">
        <AssetCell row={row} />
      </div>
      <div className="hidden text-right text-xs text-muted sm:block">
        {qtyLabel(row.asset, row.holding.shares).main}
        {row.holding.shares > 0 && (
          <div>
            <Money amount={row.value} currency={row.asset.currency} />
          </div>
        )}
      </div>
      <Badge>{assetKindInfo(row.asset.kind).label}</Badge>
      <Button
        variant="ghost"
        size="sm"
        loading={pending}
        onClick={() =>
          startTransition(async () => {
            const r = await setAssetArchived(row.asset.id, false);
            setError(r.ok ? null : r.error);
          })
        }
      >
        {!pending && <ArchiveRestore className="h-3.5 w-3.5" />} Aktifkan
      </Button>
      {error && <span className="text-xs text-expense">{error}</span>}
    </li>
  );
}
