"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Archive, ArchiveRestore, ArrowLeft, CircleAlert, Pencil, Plus, Trash2, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/misc";
import { Money } from "@/components/money/money";
import { PendingBar } from "@/components/pending-bar";
import { assetKindInfo, deriveHolding, tradeCashEffect, TRADE_TYPE_LABELS, type TradeType } from "@/lib/investments";
import type { AssetDetail } from "@/lib/investments-server";
import { cn } from "@/lib/utils";
import { deleteAsset, deleteTrade, fetchAssetDetail, setAssetArchived } from "../actions";
import { AssetFormDialog } from "../asset-form";
import { TradeFormDialog } from "../trade-form";
import { ConfirmDialog, ManualPriceDialog } from "../dialogs";
import { fmtDate, fmtDateTime, fmtNum, fmtPct, fmtPrice, plTone, qtyLabel } from "../format";
import type { TradeDTO, WalletOption } from "../types";

const TYPE_BADGE: Record<string, "income" | "expense" | "primary" | "default"> = {
  buy: "primary",
  sell: "expense",
  dividend: "income",
  split: "default",
  fee: "default",
};

export function AssetDetailView({
  detail,
  wallets,
  cashWallets,
}: {
  detail: AssetDetail;
  wallets: WalletOption[];
  cashWallets: Record<string, string>;
}) {
  const router = useRouter();
  const { asset, holding, valuation, quote, trades } = detail;
  const cur = asset.currency;
  const [tradeOpen, setTradeOpen] = React.useState(false);
  const [editTrade, setEditTrade] = React.useState<TradeDTO | null>(null);
  const [delTrade, setDelTrade] = React.useState<TradeDTO | null>(null);
  const [editing, setEditing] = React.useState(false);
  const [priceOpen, setPriceOpen] = React.useState(false);
  const [deleting, setDeleting] = React.useState(false);
  const [refreshing, startRefresh] = React.useTransition();
  const [archiving, startArchive] = React.useTransition();

  // Refresh a stale cached quote once after mount.
  const done = React.useRef(false);
  const stale = asset.priceMode === "auto" && (quote?.stale ?? true);
  React.useEffect(() => {
    if (done.current || !stale) return;
    done.current = true;
    startRefresh(async () => {
      const r = await fetchAssetDetail(asset.id);
      if (r.ok) startRefresh(() => router.refresh());
    });
  }, [stale, asset.id, router]);

  const q = qtyLabel(asset, holding.shares);
  const dividends = trades.filter((t) => t.type === "dividend");
  const splits = trades.filter((t) => t.type === "split");
  const kind = assetKindInfo(asset.kind);

  return (
    <div className="space-y-6">
      <PendingBar pending={refreshing} label="Memperbarui harga…" />
      <Link href="/investments" className="inline-flex items-center gap-1 text-sm font-medium text-muted hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Investasi
      </Link>

      {/* Header quote */}
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-2xl font-bold tracking-tight text-foreground">{asset.symbol}</h1>
            <Badge>{kind.label}</Badge>
            {asset.archived && <Badge variant="expense">Diarsipkan</Badge>}
          </div>
          {asset.name && <p className="mt-0.5 truncate text-sm text-muted">{asset.name}</p>}
          <div className="mt-3 flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <span className="text-3xl font-bold tracking-tight text-foreground" data-testid="asset-price">
              {valuation.price != null ? fmtPrice(valuation.price, cur) : "–"}
            </span>
            {asset.priceMode === "auto" && valuation.dayChangePct != null && quote?.change != null && (
              <span className={cn("text-sm font-semibold", plTone(quote.change))}>
                {quote.change > 0 ? "+" : quote.change < 0 ? "−" : ""}
                {fmtPrice(Math.abs(quote.change), cur)} ({fmtPct(valuation.dayChangePct)})
              </span>
            )}
          </div>
          <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted">
            {asset.priceMode === "manual" ? (
              <>
                <span>{asset.manualPriceAt ? `harga manual per ${fmtDate(asset.manualPriceAt)}` : "belum ada harga manual"}</span>
                <button type="button" onClick={() => setPriceOpen(true)} className="font-medium text-primary hover:underline">
                  Perbarui harga
                </button>
              </>
            ) : quote?.price != null ? (
              <>
                <span>
                  Harga per {quote.asOf ? fmtDateTime(quote.asOf) : "–"}
                  {quote.fetchedAt ? ` · diperbarui ${fmtDateTime(quote.fetchedAt)}` : ""}
                </span>
                {quote.stale && <span className="rounded-full bg-amber-100 px-2 py-0.5 font-medium text-amber-800">usang</span>}
              </>
            ) : (
              <span>{refreshing ? "Mengambil harga…" : "Harga pasar belum tersedia — nilai dihitung dari modal."}</span>
            )}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => setTradeOpen(true)}>
            <Plus className="h-4 w-4" /> Catat transaksi
          </Button>
          <Button variant="outline" size="icon" onClick={() => setEditing(true)} aria-label="Ubah aset" title="Ubah aset">
            <Pencil className="h-4 w-4" />
          </Button>
          <Button
            variant="outline"
            size="icon"
            loading={archiving}
            onClick={() => startArchive(async () => void (await setAssetArchived(asset.id, !asset.archived)))}
            aria-label={asset.archived ? "Aktifkan aset" : "Arsipkan aset"}
            title={asset.archived ? "Aktifkan aset" : "Arsipkan aset"}
          >
            {asset.archived ? <ArchiveRestore className="h-4 w-4" /> : <Archive className="h-4 w-4" />}
          </Button>
          <Button variant="outline" size="icon" onClick={() => setDeleting(true)} aria-label="Hapus aset" title="Hapus aset">
            <Trash2 className="h-4 w-4 text-expense" />
          </Button>
        </div>
      </header>

      {holding.issues.length > 0 && (
        <p className="flex items-start gap-2 rounded-lg bg-amber-50 p-3 text-sm text-amber-800" role="alert">
          <CircleAlert className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            Riwayat tidak konsisten: {holding.issues[0].message} per {fmtDate(holding.issues[0].date)}. Periksa transaksi jual/beli.
          </span>
        </p>
      )}

      {/* Position & P/L */}
      <section className="grid gap-4 lg:grid-cols-3" aria-label="Posisi">
        <div className="rounded-card border border-border bg-card p-5 shadow-sm">
          <h2 className="text-sm font-medium text-muted">Posisi</h2>
          <p className="mt-1 text-2xl font-bold tracking-tight text-foreground" data-testid="position-qty">
            {q.main}
          </p>
          {q.sub && <p className="text-sm text-muted">{q.sub}</p>}
          <dl className="mt-4 space-y-2 text-sm">
            <Row label="Harga rata-rata">{holding.avgPrice != null ? <Money amount={holding.avgPrice} currency={cur} /> : "–"}</Row>
            <Row label="Modal">
              <Money amount={holding.cost} currency={cur} />
            </Row>
            <Row label="Nilai pasar" strong>
              {valuation.marketValue != null ? <Money amount={valuation.marketValue} currency={cur} /> : "–"}
            </Row>
            {asset.walletId && (
              <Row label="Dompet">
                <span className="inline-flex items-center gap-1">
                  <Wallet className="h-3.5 w-3.5 text-muted" />
                  {wallets.find((w) => w.id === asset.walletId)?.name ?? "–"}
                </span>
              </Row>
            )}
          </dl>
        </div>
        <div className="rounded-card border border-border bg-card p-5 shadow-sm lg:col-span-2" data-testid="pl-breakdown">
          <h2 className="text-sm font-medium text-muted">Laba/rugi</h2>
          <dl className="mt-3 grid gap-x-8 gap-y-2 text-sm sm:grid-cols-2">
            <Row label="Belum terealisasi" tone={valuation.unrealized}>
              {valuation.unrealized != null ? (
                <>
                  <Money amount={valuation.unrealized} currency={cur} sign="auto" /> ({fmtPct(valuation.unrealizedPct)})
                </>
              ) : (
                "–"
              )}
            </Row>
            <Row label="Hari ini" tone={valuation.dayChange}>
              {valuation.dayChange != null ? <Money amount={valuation.dayChange} currency={cur} sign="auto" /> : "–"}
            </Row>
            <Row label="Terealisasi" tone={holding.realized}>
              <Money amount={holding.realized} currency={cur} sign="auto" />
            </Row>
            <Row label="Dividen">
              <Money amount={holding.dividends} currency={cur} />
            </Row>
            <Row label="Total biaya">
              <Money amount={holding.fees} currency={cur} />
            </Row>
            <Row label="Total imbal hasil" tone={valuation.totalReturn} strong>
              <Money amount={valuation.totalReturn} currency={cur} sign="auto" />
            </Row>
            <Row label="Total dibeli">
              <Money amount={holding.invested} currency={cur} />
            </Row>
            <Row label="Total dijual">
              <Money amount={holding.proceeds} currency={cur} />
            </Row>
          </dl>
        </div>
      </section>

      {/* Trades */}
      <section aria-label="Riwayat transaksi">
        <h2 className="mb-3 text-base font-semibold text-foreground">Riwayat transaksi</h2>
        {trades.length === 0 ? (
          <div className="rounded-card border border-dashed border-border p-8 text-center">
            <p className="text-sm text-muted">Belum ada transaksi. Catat pembelian pertama untuk mulai menghitung kepemilikan.</p>
            <Button className="mt-4" onClick={() => setTradeOpen(true)}>
              <Plus className="h-4 w-4" /> Catat pembelian
            </Button>
          </div>
        ) : (
          <ul className="divide-y divide-border rounded-card border border-border bg-card shadow-sm" data-testid="trade-list">
            {trades.map((t) => (
              <TradeRow key={t.id} t={t} unit={asset} walletName={t.cashTransactionId ? cashWallets[t.cashTransactionId] : undefined} onEdit={() => setEditTrade(t)} onDelete={() => setDelTrade(t)} />
            ))}
          </ul>
        )}
      </section>

      {(dividends.length > 0 || splits.length > 0) && (
        <section className="grid gap-4 md:grid-cols-2">
          {dividends.length > 0 && (
            <div className="rounded-card border border-border bg-card p-5 shadow-sm">
              <div className="mb-3 flex items-center justify-between">
                <h2 className="text-base font-semibold text-foreground">Dividen</h2>
                <span className="text-sm font-semibold text-income">
                  <Money amount={holding.dividends} currency={cur} />
                </span>
              </div>
              <ul className="space-y-2 text-sm">
                {dividends.map((d) => (
                  <li key={d.id} className="flex justify-between gap-2">
                    <span className="text-muted">{fmtDate(d.date)}</span>
                    <span className="font-medium text-foreground">
                      <Money amount={d.amount ?? 0} currency={cur} />
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {splits.length > 0 && (
            <div className="rounded-card border border-border bg-card p-5 shadow-sm">
              <h2 className="mb-3 text-base font-semibold text-foreground">Stock split</h2>
              <ul className="space-y-2 text-sm">
                {splits.map((s) => (
                  <li key={s.id} className="flex justify-between gap-2">
                    <span className="text-muted">{fmtDate(s.date)}</span>
                    <span className="font-medium text-foreground">{splitLabel(s.ratio ?? 1)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </section>
      )}

      <TradeFormDialog
        open={tradeOpen || !!editTrade}
        onClose={() => {
          setTradeOpen(false);
          setEditTrade(null);
        }}
        asset={asset}
        holding={holding}
        trades={trades}
        lastPrice={valuation.price}
        wallets={wallets}
        trade={editTrade ?? undefined}
      />
      <AssetFormDialog open={editing} onClose={() => setEditing(false)} wallets={wallets} asset={asset} />
      <ManualPriceDialog open={priceOpen} asset={asset} onClose={() => setPriceOpen(false)} />

      {delTrade && (
        <ConfirmDialog
          open
          onClose={() => setDelTrade(null)}
          title="Hapus transaksi"
          confirmLabel="Hapus transaksi"
          onConfirm={() => deleteTrade(delTrade.id)}
        >
          <DeleteTradeText t={delTrade} trades={trades} asset={asset} walletName={delTrade.cashTransactionId ? cashWallets[delTrade.cashTransactionId] : undefined} />
        </ConfirmDialog>
      )}

      <ConfirmDialog
        open={deleting}
        onClose={() => setDeleting(false)}
        title={`Hapus ${asset.symbol}?`}
        confirmLabel="Hapus permanen"
        onConfirm={async () => {
          const r = await deleteAsset(asset.id);
          if (r.ok) router.push("/investments");
          return r;
        }}
        alternative={
          asset.archived
            ? undefined
            : {
                label: "Arsipkan saja",
                run: () => setAssetArchived(asset.id, true),
              }
        }
      >
        <p className="font-medium">Tidak bisa dibatalkan.</p>
        <p className="text-expense/90">
          Semua {trades.length} transaksi aset ini dihapus
          {trades.some((t) => t.cashTransactionId) ? ", beserta transaksi kas terkait di dompet — saldo dompet dikembalikan seperti sebelum transaksi" : ""}.
        </p>
        {!asset.archived && <p className="text-expense/90">Sarankan: arsipkan untuk menyembunyikan aset tanpa menghapus riwayat dan saldo.</p>}
      </ConfirmDialog>
    </div>
  );
}

function Row({ label, children, tone, strong }: { label: string; children: React.ReactNode; tone?: number | null; strong?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className="text-muted">{label}</dt>
      <dd className={cn("text-right", strong ? "font-bold" : "font-medium", tone === undefined ? "text-foreground" : plTone(tone))}>{children}</dd>
    </div>
  );
}

function splitLabel(ratio: number) {
  return ratio >= 1 ? `1 : ${fmtNum(ratio)}` : `${fmtNum(1 / ratio)} : 1`;
}

function tradeSummary(t: TradeDTO, asset: { kind: string; unit: string; currency: string }) {
  if (t.type === "buy" || t.type === "sell") {
    return (
      <>
        {qtyLabel(asset, t.quantity ?? 0).main} @ {fmtPrice(t.price ?? 0, asset.currency)}
        {t.fee > 0 && (
          <span className="text-muted">
            {" "}
            · biaya <Money amount={t.fee} currency={asset.currency} />
          </span>
        )}
      </>
    );
  }
  if (t.type === "split") return <>Split {splitLabel(t.ratio ?? 1)}</>;
  return <Money amount={t.amount ?? 0} currency={asset.currency} />;
}

function TradeRow({
  t,
  unit,
  walletName,
  onEdit,
  onDelete,
}: {
  t: TradeDTO;
  unit: { kind: string; unit: string; currency: string };
  walletName?: string;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const effect = tradeCashEffect(t);
  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-1 p-3 sm:flex-nowrap" data-testid={`trade-${t.type}`}>
      <div className="w-24 shrink-0 text-xs text-muted">{fmtDate(t.date)}</div>
      <Badge variant={TYPE_BADGE[t.type] ?? "default"} className="shrink-0">
        {TRADE_TYPE_LABELS[t.type as TradeType] ?? t.type}
      </Badge>
      <div className="min-w-0 flex-1 basis-full text-sm text-foreground sm:basis-auto">
        <div className="truncate">{tradeSummary(t, unit)}</div>
        <div className="truncate text-xs text-muted">
          {t.cashTransactionId && effect ? (
            <>
              Kas{walletName ? ` ${walletName}` : ""}:{" "}
              <span className={effect.amount < 0 ? "text-expense" : "text-income"}>
                <Money amount={effect.amount} currency={unit.currency} sign="auto" />
              </span>
            </>
          ) : t.type === "split" ? (
            "Tanpa efek kas"
          ) : (
            "Tidak dicatat di dompet"
          )}
          {t.note ? ` · ${t.note}` : ""}
        </div>
      </div>
      <div className="ml-auto flex shrink-0 gap-1">
        <Button variant="ghost" size="icon" onClick={onEdit} aria-label="Ubah transaksi" title="Ubah">
          <Pencil className="h-4 w-4" />
        </Button>
        <Button variant="ghost" size="icon" onClick={onDelete} aria-label="Hapus transaksi" title="Hapus">
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>
    </li>
  );
}

function DeleteTradeText({ t, trades, asset, walletName }: { t: TradeDTO; trades: TradeDTO[]; asset: { currency: string }; walletName?: string }) {
  const effect = tradeCashEffect(t);
  const before = deriveHolding(trades).issues.length;
  const after = deriveHolding(trades.filter((x) => x.id !== t.id)).issues.length;
  return (
    <>
      <p className="font-medium">
        {TRADE_TYPE_LABELS[t.type as TradeType]} {fmtDate(t.date)} akan dihapus.
      </p>
      {t.cashTransactionId && effect ? (
        <p className="text-expense/90">
          Transaksi kas terkait{walletName ? ` di ${walletName}` : ""} ikut dihapus — saldo dompet {effect.amount < 0 ? "bertambah kembali" : "berkurang"}{" "}
          <Money amount={Math.abs(effect.amount)} currency={asset.currency} />.
        </p>
      ) : (
        <p className="text-expense/90">Tidak ada transaksi kas terkait; saldo dompet tidak berubah.</p>
      )}
      {after > before && <p className="text-expense/90">Perhatian: penjualan setelahnya akan melebihi kepemilikan.</p>}
    </>
  );
}
