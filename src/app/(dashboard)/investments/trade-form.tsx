"use client";

import * as React from "react";
import { ArrowRight, CircleAlert } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/input";
import { Money } from "@/components/money/money";
import {
  deriveHolding,
  FEE_PRESETS,
  isWholeLots,
  lotsToShares,
  roundMoney,
  sharesToLots,
  tradeCashEffect,
  TRADE_TYPE_LABELS,
  type TradeLike,
  type TradeType,
} from "@/lib/investments";
import { cn } from "@/lib/utils";
import { createTrade, updateTrade } from "./actions";
import { Segmented } from "./charts";
import { dateKeyWIB, fmtNum, fmtPrice, qtyLabel, plTone } from "./format";
import { sortWallets, type AssetDTO, type Holding, type TradeDTO, type WalletOption } from "./types";

const TYPES: TradeType[] = ["buy", "sell", "dividend", "split", "fee"];
const RATE_KEY = "ghina.feeRates";
const NEW_ID = "__new__";

function loadRates(): { buy: number; sell: number } {
  try {
    const v = JSON.parse(localStorage.getItem(RATE_KEY) ?? "null");
    if (v && typeof v.buy === "number" && typeof v.sell === "number") return v;
  } catch {}
  return { ...FEE_PRESETS };
}
function saveRates(r: { buy: number; sell: number }) {
  try {
    localStorage.setItem(RATE_KEY, JSON.stringify(r));
  } catch {}
}

export type TradeFormProps = {
  asset: AssetDTO;
  holding: Holding;
  /** The asset's trades, for an exact preview (else derived from `holding`). */
  trades?: TradeDTO[];
  lastPrice: number | null;
  wallets: WalletOption[];
  /** Edit this trade. */
  trade?: TradeDTO;
  defaultType?: TradeType;
};

export function TradeFormDialog({ open, onClose, ...props }: TradeFormProps & { open: boolean; onClose: () => void }) {
  const title = props.trade ? `Ubah transaksi ${props.asset.symbol}` : `Transaksi ${props.asset.symbol}`;
  return (
    <Modal open={open} onClose={onClose} title={title} className="sm:max-w-lg">
      {open && <TradeForm {...props} onClose={onClose} />}
    </Modal>
  );
}

const num = (s: string) => (s.trim() === "" ? NaN : Number(s));

function TradeForm({ asset, holding, trades, lastPrice, wallets, trade, defaultType = "buy", onClose }: TradeFormProps & { onClose: () => void }) {
  const isStock = asset.kind === "stock";
  const sorted = sortWallets(wallets);
  const [type, setType] = React.useState<TradeType>((trade?.type as TradeType) ?? defaultType);
  const [qtyMode, setQtyMode] = React.useState<"lot" | "unit">(
    isStock && (!trade?.quantity || isWholeLots(trade.quantity)) ? "lot" : "unit",
  );
  const [qty, setQty] = React.useState(() => {
    if (trade?.quantity == null) return "";
    return String(isStock && isWholeLots(trade.quantity) ? sharesToLots(trade.quantity) : trade.quantity);
  });
  const [price, setPrice] = React.useState(trade?.price != null ? String(trade.price) : lastPrice != null ? String(lastPrice) : "");
  const [rates, setRates] = React.useState<{ buy: number; sell: number }>(() => ({ ...FEE_PRESETS }));
  const [fee, setFee] = React.useState(trade ? String(trade.fee) : "");
  const [feeTouched, setFeeTouched] = React.useState(!!trade);
  const [amount, setAmount] = React.useState(trade?.amount != null ? String(trade.amount) : "");
  const [ratio, setRatio] = React.useState(trade?.ratio != null ? String(trade.ratio) : "");
  const origDate = trade ? dateKeyWIB(trade.date) : null;
  const [date, setDate] = React.useState(origDate ?? dateKeyWIB());
  const [note, setNote] = React.useState(trade?.note ?? "");
  const [cashOn, setCashOn] = React.useState(trade ? !!trade.cashTransactionId : !!asset.walletId);
  const keepWallet = !!trade?.cashTransactionId;
  const [walletId, setWalletId] = React.useState(keepWallet ? "" : (asset.walletId ?? sorted.find((w) => w.type === "investment")?.id ?? ""));
  const [error, setError] = React.useState<string | null>(null);
  const [pending, startTransition] = React.useTransition();

  // Per-user fee rates are a browser preference (docs/investments.md, clarification 9).
  React.useEffect(() => {
    const r = loadRates();
    // eslint-disable-next-line react-hooks/set-state-in-effect -- one-time read of browser storage after mount
    setRates(r);
  }, []);

  const trading = type === "buy" || type === "sell";
  const quantity = trading ? (isStock && qtyMode === "lot" ? lotsToShares(num(qty)) : num(qty)) : NaN;
  const priceN = num(price);
  const gross = trading && quantity > 0 && priceN > 0 ? quantity * priceN : 0;
  const side = type === "sell" ? "sell" : "buy";
  const autoFee = roundMoney(gross * rates[side]);
  const feeN = trading ? (feeTouched ? (fee.trim() === "" ? 0 : num(fee)) : autoFee) : 0;

  const draft: TradeLike = {
    id: trade?.id ?? NEW_ID,
    type,
    date: `${date}T12:00:00+07:00`,
    quantity: trading ? quantity : null,
    price: trading ? priceN : null,
    fee: trading ? feeN : 0,
    amount: type === "dividend" || type === "fee" ? num(amount) : null,
    ratio: type === "split" ? num(ratio) : null,
    createdAt: trade?.createdAt ?? null,
  };
  const valid =
    trading
      ? quantity > 0 && priceN > 0 && feeN >= 0
      : type === "split"
        ? (draft.ratio ?? 0) > 0 && draft.ratio !== 1
        : (draft.amount ?? 0) > 0;

  // Preview: the holding before/after this trade (exact when the trade list is known).
  const base: TradeLike[] = trades
    ? trades.filter((t) => t.id !== trade?.id)
    : holding.shares > 0
      ? [{ id: "__base__", type: "buy", date: "1970-01-01T00:00:00Z", quantity: holding.shares, price: holding.avgPrice ?? 0, fee: 0, amount: null, ratio: null }]
      : [];
  const before = deriveHolding(base);
  const after = valid ? deriveHolding([...base, draft]) : null;
  const issue = after?.issues.find((i) => i.tradeId === (trade?.id ?? NEW_ID)) ?? null;

  const effect = valid && type !== "split" ? tradeCashEffect(draft) : null;
  const cashWallet = walletId ? wallets.find((w) => w.id === walletId) : null;
  const showCash = type !== "split";

  function onTypeChange(t: TradeType) {
    setType(t);
    setError(null);
    if ((t === "buy" || t === "sell") && !price && lastPrice != null) setPrice(String(lastPrice));
  }

  function setRate(pct: string) {
    const v = Number(pct) / 100;
    if (!(Number.isFinite(v) && v >= 0 && v < 0.2)) return;
    const next = { ...rates, [side]: v };
    setRates(next);
    saveRates(next);
    setFeeTouched(false);
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!valid) return setError(trading ? "Isi jumlah dan harga lebih dari 0" : type === "split" ? "Rasio split harus lebih dari 0 dan bukan 1" : "Nominal harus lebih dari 0");
    if (issue) return setError(`${issue.message}.`);
    let cash: { walletId?: string | null } | false | undefined;
    if (!showCash || !cashOn) cash = false;
    else if (walletId) cash = { walletId };
    else if (keepWallet) cash = undefined;
    else return setError("Pilih dompet untuk efek kas");
    const input = {
      assetId: asset.id,
      type,
      date,
      quantity: draft.quantity,
      price: draft.price,
      fee: draft.fee,
      amount: draft.amount,
      ratio: draft.ratio,
      note: note.trim() || null,
    };
    startTransition(async () => {
      const r = trade
        ? await updateTrade(trade.id, date === origDate ? { ...input, date: undefined } : input, cash)
        : await createTrade(input, cash);
      if (!r.ok) return setError(r.error);
      onClose();
    });
  }

  const unitLabel = isStock ? (qtyMode === "lot" ? "lot" : "lembar") : asset.unit;

  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="grid grid-cols-5 gap-1 rounded-lg bg-accent p-1" role="radiogroup" aria-label="Jenis transaksi">
        {TYPES.map((t) => (
          <button
            key={t}
            type="button"
            role="radio"
            aria-checked={type === t}
            onClick={() => onTypeChange(t)}
            className={cn(
              "truncate rounded-md px-1 py-1.5 text-xs font-medium transition sm:text-sm",
              type === t ? "bg-card text-foreground shadow-sm" : "text-muted hover:text-foreground",
            )}
          >
            {t === "split" ? "Split" : TRADE_TYPE_LABELS[t]}
          </button>
        ))}
      </div>

      {trading && (
        <>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <div className="mb-1.5 flex items-center justify-between gap-2">
                <span className="text-sm font-medium text-foreground">Jumlah</span>
                {isStock && (
                  <Segmented
                    label="Satuan jumlah"
                    value={qtyMode}
                    onChange={(m) => {
                      const n = num(qty);
                      if (Number.isFinite(n) && m !== qtyMode) setQty(String(m === "lot" ? sharesToLots(n) : lotsToShares(n)));
                      setQtyMode(m);
                    }}
                    options={[
                      { value: "lot", label: "Lot" },
                      { value: "unit", label: "Lembar" },
                    ]}
                  />
                )}
              </div>
              <Input
                type="number"
                inputMode="decimal"
                min={0}
                step="any"
                value={qty}
                onChange={(e) => setQty(e.target.value)}
                placeholder={`0 ${unitLabel}`}
                aria-label={`Jumlah (${unitLabel})`}
                autoFocus
              />
              {isStock && qtyMode === "lot" && quantity > 0 && <p className="mt-1 text-xs text-muted">= {fmtNum(quantity)} lembar</p>}
            </div>
            <Field label={`Harga per ${isStock ? "lembar" : asset.unit}`}>
              <Input type="number" inputMode="decimal" min={0} step="any" value={price} onChange={(e) => setPrice(e.target.value)} aria-label="Harga per unit" />
              {lastPrice != null && <p className="mt-1 text-xs text-muted">Terakhir {fmtPrice(lastPrice, asset.currency)}</p>}
            </Field>
          </div>

          <div>
            <div className="mb-1.5 flex items-center justify-between gap-2">
              <span className="text-sm font-medium text-foreground">Biaya broker + pajak</span>
              <label className="flex items-center gap-1 text-xs text-muted">
                Tarif
                <input
                  type="number"
                  step="0.01"
                  min={0}
                  max={20}
                  key={`${side}-${rates[side]}`}
                  defaultValue={roundMoney(rates[side] * 100 * 100) / 100}
                  onBlur={(e) => setRate(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      setRate((e.target as HTMLInputElement).value);
                    }
                  }}
                  aria-label="Tarif biaya (%)"
                  className="h-7 w-16 rounded-md border border-border bg-surface px-1.5 text-right text-xs text-foreground"
                />
                %
              </label>
            </div>
            <Input
              type="number"
              inputMode="decimal"
              min={0}
              step="any"
              value={feeTouched ? fee : String(autoFee)}
              onChange={(e) => {
                setFeeTouched(true);
                setFee(e.target.value);
              }}
              aria-label="Biaya"
            />
            <p className="mt-1 text-xs text-muted">
              {feeTouched ? (
                <button type="button" className="font-medium text-primary hover:underline" onClick={() => setFeeTouched(false)}>
                  Pakai estimasi {fmtNum(rates[side] * 100, 2)}%
                </button>
              ) : (
                <>Estimasi {fmtNum(rates[side] * 100, 2)}% dari nilai transaksi (bisa diubah).</>
              )}
            </p>
          </div>
        </>
      )}

      {(type === "dividend" || type === "fee") && (
        <Field label={type === "dividend" ? "Dividen diterima (bersih)" : "Nominal biaya"}>
          <Input type="number" inputMode="decimal" min={0} step="any" value={amount} onChange={(e) => setAmount(e.target.value)} autoFocus aria-label="Nominal" />
          {type === "fee" && <p className="mt-1 text-xs text-muted">Biaya lain di luar beli/jual (mis. kustodian). Mengurangi laba terealisasi.</p>}
        </Field>
      )}

      {type === "split" && (
        <Field label="Rasio split">
          <div className="flex items-center gap-2 text-sm text-muted">
            <span className="shrink-0">1 lama →</span>
            <Input type="number" inputMode="decimal" min={0} step="any" value={ratio} onChange={(e) => setRatio(e.target.value)} placeholder="2" autoFocus aria-label="Rasio split" className="w-28" />
            <span className="shrink-0">baru</span>
          </div>
          <p className="mt-1 text-xs text-muted">Contoh: split 1:5 → isi 5. Reverse split 5:1 → isi 0,2. Modal tidak berubah.</p>
        </Field>
      )}

      <div className="grid grid-cols-2 gap-3">
        <Field label="Tanggal">
          <Input type="date" value={date} max={dateKeyWIB()} onChange={(e) => setDate(e.target.value)} required aria-label="Tanggal transaksi" />
        </Field>
        <Field label="Catatan">
          <Input value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} placeholder="Opsional" />
        </Field>
      </div>

      {showCash && (
        <div className="space-y-2 rounded-lg border border-border p-3">
          <label className="flex items-center gap-2 text-sm font-medium text-foreground">
            <input type="checkbox" checked={cashOn} onChange={(e) => setCashOn(e.target.checked)} className="h-4 w-4 accent-[var(--color-primary)]" aria-label="Catat di dompet" />
            Catat di dompet (efek kas)
          </label>
          {cashOn && (
            <>
              <Select value={walletId} onChange={(e) => setWalletId(e.target.value)} aria-label="Dompet efek kas">
                {keepWallet ? <option value="">Dompet saat ini (tidak berubah)</option> : <option value="">Pilih dompet…</option>}
                {sorted.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name}
                    {w.currency !== asset.currency ? ` (${w.currency})` : ""}
                  </option>
                ))}
              </Select>
              {effect && (
                <div className="text-sm" data-testid="cash-preview">
                  <p className="flex flex-wrap items-center gap-x-1.5">
                    <span className="text-muted">{effect.amount < 0 ? "Kas keluar" : type === "dividend" ? "Pemasukan dividen" : "Kas masuk"}</span>
                    <span className={cn("font-semibold", effect.amount < 0 ? "text-expense" : "text-income")}>
                      <Money amount={effect.amount} currency={asset.currency} sign="auto" reveal />
                    </span>
                  </p>
                  {cashWallet && !trade && (
                    <p className="mt-0.5 flex flex-wrap items-center gap-x-1.5 text-xs text-muted">
                      Saldo {cashWallet.name}: <Money amount={cashWallet.balance} currency={cashWallet.currency} />
                      <ArrowRight className="h-3 w-3" />
                      <span className={cn(cashWallet.balance + effect.amount < 0 && "font-medium text-expense")}>
                        <Money amount={cashWallet.balance + effect.amount} currency={cashWallet.currency} />
                      </span>
                    </p>
                  )}
                  {cashWallet && cashWallet.currency !== asset.currency && (
                    <p className="mt-0.5 text-xs text-amber-600">Mata uang dompet berbeda — nominal dipindahkan apa adanya (tanpa kurs).</p>
                  )}
                </div>
              )}
            </>
          )}
          {!cashOn && trade?.cashTransactionId && (
            <p className="text-xs text-amber-600">Transaksi kas terkait akan dihapus dan saldo dompet dikembalikan.</p>
          )}
        </div>
      )}

      {issue ? (
        <p className="flex items-start gap-2 rounded-lg bg-expense-soft p-3 text-sm text-expense" role="alert" data-testid="sell-guard">
          <CircleAlert className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            {issue.message}. Anda memiliki {qtyLabel(asset, before.shares).main} saat ini.
          </span>
        </p>
      ) : (
        after && <HoldingPreview asset={asset} before={before} after={after} type={type} />
      )}

      {error && !issue && <p className="text-sm text-expense" role="alert">{error}</p>}

      <div className="flex justify-end gap-2 pt-1">
        <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
          Batal
        </Button>
        <Button type="submit" loading={pending} disabled={!!issue}>
          {pending ? "Menyimpan…" : trade ? "Simpan perubahan" : `Simpan ${TRADE_TYPE_LABELS[type].toLowerCase()}`}
        </Button>
      </div>
    </form>
  );
}

function HoldingPreview({ asset, before, after, type }: { asset: AssetDTO; before: Holding; after: Holding; type: TradeType }) {
  const realizedDelta = after.realized - before.realized;
  return (
    <div className="rounded-lg bg-accent/60 p-3 text-sm" data-testid="holding-preview">
      <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-muted">Setelah transaksi</p>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-1">
        <dt className="text-muted">Kepemilikan</dt>
        <dd className="text-right font-medium text-foreground">{qtyLabel(asset, after.shares).main}</dd>
        <dt className="text-muted">Harga rata-rata</dt>
        <dd className="text-right font-medium text-foreground">
          {after.avgPrice != null ? <Money amount={after.avgPrice} currency={asset.currency} /> : "–"}
        </dd>
        <dt className="text-muted">Modal</dt>
        <dd className="text-right font-medium text-foreground">
          <Money amount={after.cost} currency={asset.currency} />
        </dd>
        {(type === "sell" || type === "fee") && (
          <>
            <dt className="text-muted">Laba/rugi terealisasi</dt>
            <dd className={cn("text-right font-semibold", plTone(realizedDelta))}>
              <Money amount={realizedDelta} currency={asset.currency} sign="auto" />
            </dd>
          </>
        )}
      </dl>
    </div>
  );
}
