"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, CircleAlert, Loader2 } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/input";
import { ASSET_KINDS, assetKindInfo, isAutoKind, normalizeSymbol, type AssetKind } from "@/lib/investments";
import { cn } from "@/lib/utils";
import { createAsset, lookupSymbol, updateAsset } from "./actions";
import { dateKeyWIB, fmtPrice } from "./format";
import { sortWallets, type AssetDTO, type WalletOption } from "./types";

type Lookup =
  | { state: "idle" }
  | { state: "checking" }
  | { state: "ok"; name: string | null; price: number | null; symbol: string }
  | { state: "not_found"; symbol: string }
  | { state: "unavailable" }
  | { state: "invalid"; error: string };

/** Add (no `asset`) or edit an asset. Stock/crypto codes are validated live against the price service. */
export function AssetFormDialog({
  open,
  onClose,
  wallets,
  asset,
}: {
  open: boolean;
  onClose: () => void;
  wallets: WalletOption[];
  asset?: AssetDTO;
}) {
  return (
    <Modal open={open} onClose={onClose} title={asset ? `Ubah ${asset.symbol}` : "Tambah aset"} className="sm:max-w-lg">
      {/* Remount per open so the form starts fresh. */}
      {open && <AssetForm onClose={onClose} wallets={wallets} asset={asset} />}
    </Modal>
  );
}

function AssetForm({ onClose, wallets, asset }: { onClose: () => void; wallets: WalletOption[]; asset?: AssetDTO }) {
  const router = useRouter();
  const sorted = sortWallets(wallets);
  const editing = !!asset;
  const [kind, setKind] = React.useState<AssetKind>((asset?.kind as AssetKind) ?? "stock");
  const [symbol, setSymbol] = React.useState(asset?.symbol ?? "");
  const [name, setName] = React.useState(asset?.name ?? "");
  const [manual, setManual] = React.useState(asset ? asset.priceMode === "manual" : false);
  const [price, setPrice] = React.useState(asset?.manualPrice != null ? String(asset.manualPrice) : "");
  const [priceDate, setPriceDate] = React.useState(asset?.manualPriceAt ? dateKeyWIB(asset.manualPriceAt) : dateKeyWIB());
  const [unit, setUnit] = React.useState(asset?.unit ?? "");
  const [walletId, setWalletId] = React.useState(asset ? (asset.walletId ?? "") : (sorted.find((w) => w.type === "investment")?.id ?? ""));
  const [lookup, setLookup] = React.useState<Lookup>({ state: "idle" });
  const [error, setError] = React.useState<string | null>(null);
  const [pending, startTransition] = React.useTransition();

  const auto = isAutoKind(kind) && !manual;
  const canLookup = isAutoKind(kind) && !editing && !manual;

  // Debounced live validation of the ticker (server-side price service; cached).
  React.useEffect(() => {
    if (!canLookup) return;
    const raw = symbol.trim();
    if (raw.length < 2) return;
    const n = normalizeSymbol(kind, raw);
    let cancelled = false;
    const t = setTimeout(async () => {
      if (!n.ok) {
        setLookup({ state: "invalid", error: n.error });
        return;
      }
      setLookup({ state: "checking" });
      const r = await lookupSymbol(kind as "stock" | "crypto", n.symbol).catch(() => null);
      if (cancelled) return;
      if (!r || !r.ok) setLookup(r && !r.ok ? { state: "invalid", error: r.error } : { state: "unavailable" });
      else if (r.status === "ok") setLookup({ state: "ok", name: r.quote?.name ?? null, price: r.quote?.price ?? null, symbol: r.symbol });
      else if (r.status === "not_found") setLookup({ state: "not_found", symbol: r.symbol });
      else setLookup({ state: "unavailable" });
    }, 700);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [symbol, kind, canLookup]);

  const lookupShown: Lookup = canLookup && symbol.trim().length >= 2 ? lookup : { state: "idle" };
  const blocked = canLookup && (lookupShown.state === "not_found" || lookupShown.state === "invalid" || lookupShown.state === "checking");

  function pickKind(k: AssetKind) {
    setKind(k);
    setLookup({ state: "idle" });
    if (!isAutoKind(k)) setManual(true);
    else setManual(false);
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const p = price.trim() === "" ? null : Number(price);
    if (!auto && p != null && !(Number.isFinite(p) && p >= 0)) return setError("Harga tidak valid");
    startTransition(async () => {
      const common = {
        name: name.trim() || null,
        unit: unit.trim() || null,
        walletId: walletId || null,
        priceMode: (auto ? "auto" : "manual") as "auto" | "manual",
        ...(!auto ? { manualPrice: p, manualPriceAt: p != null ? priceDate : null } : {}),
      };
      const r = editing ? await updateAsset(asset.id, common) : await createAsset({ kind, symbol: symbol.trim(), ...common });
      if (!r.ok) return setError(r.error);
      onClose();
      if (!editing && "id" in r) router.push(`/investments/${r.id}`);
    });
  }

  const info = assetKindInfo(kind);
  return (
    <form onSubmit={submit} className="space-y-4">
      {!editing && (
        <Field label="Jenis">
          <div className="grid grid-cols-3 gap-1.5" role="radiogroup" aria-label="Jenis aset">
            {ASSET_KINDS.map((k) => (
              <button
                key={k.id}
                type="button"
                role="radio"
                aria-checked={kind === k.id}
                onClick={() => pickKind(k.id)}
                className={cn(
                  "rounded-lg border px-2 py-2 text-sm font-medium transition",
                  kind === k.id ? "border-primary bg-primary-soft text-primary" : "border-border text-muted hover:bg-accent",
                )}
              >
                {k.label}
              </button>
            ))}
          </div>
        </Field>
      )}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Field label={kind === "stock" ? "Kode saham" : kind === "crypto" ? "Kode kripto" : "Kode"}>
          <Input
            value={symbol}
            onChange={(e) => {
              const v = kind === "stock" || kind === "crypto" ? e.target.value.toUpperCase() : e.target.value;
              setSymbol(v);
              setLookup(canLookup && v.trim().length >= 2 ? { state: "checking" } : { state: "idle" });
            }}
            placeholder={kind === "stock" ? "BBCA" : kind === "crypto" ? "BTC" : kind === "gold" ? "ANTAM" : "Kode singkat"}
            required
            disabled={editing}
            autoFocus={!editing}
            maxLength={20}
            aria-label="Kode aset"
            autoCapitalize="characters"
          />
        </Field>
        <Field label="Nama (opsional)">
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={lookupShown.state === "ok" && lookupShown.name ? lookupShown.name : isAutoKind(kind) ? "Terisi otomatis" : "Nama aset"}
            maxLength={100}
          />
        </Field>
      </div>

      {canLookup && <LookupHint lookup={lookupShown} kind={kind} />}

      {isAutoKind(kind) && (
        <label className="flex items-start gap-2 text-sm text-foreground">
          <input type="checkbox" checked={manual} onChange={(e) => setManual(e.target.checked)} className="mt-0.5 h-4 w-4 accent-[var(--color-primary)]" />
          <span>
            Harga manual
            <span className="block text-xs text-muted">Tidak memakai harga pasar otomatis — Anda memperbarui harga sendiri.</span>
          </span>
        </label>
      )}

      {!auto && (
        <div className="grid grid-cols-2 gap-3">
          <Field label={`Harga per ${unit.trim() || asset?.unit || info.unit}`}>
            <Input type="number" inputMode="decimal" min={0} step="any" value={price} onChange={(e) => setPrice(e.target.value)} placeholder="0" aria-label="Harga manual" />
          </Field>
          <Field label="Harga per tanggal">
            <Input type="date" value={priceDate} max={dateKeyWIB()} onChange={(e) => setPriceDate(e.target.value)} aria-label="Tanggal harga" />
          </Field>
        </div>
      )}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Field label="Satuan">
          <Input value={unit} onChange={(e) => setUnit(e.target.value)} placeholder={info.unit} maxLength={20} />
        </Field>
        <Field label="Dompet / RDN">
          <Select value={walletId} onChange={(e) => setWalletId(e.target.value)} aria-label="Dompet aset">
            <option value="">Tanpa dompet</option>
            {sorted.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name}
                {w.type === "investment" ? " (investasi)" : ""}
              </option>
            ))}
          </Select>
        </Field>
      </div>
      <p className="-mt-2 text-xs text-muted">Transaksi beli/jual/dividen memindahkan kas di dompet ini secara default.</p>

      {error && <p className="text-sm text-expense" role="alert">{error}</p>}

      <div className="flex justify-end gap-2 pt-1">
        <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
          Batal
        </Button>
        <Button type="submit" loading={pending} disabled={blocked || !symbol.trim()}>
          {pending ? "Menyimpan…" : editing ? "Simpan" : "Tambah aset"}
        </Button>
      </div>
    </form>
  );
}

function LookupHint({ lookup, kind }: { lookup: Lookup; kind: string }) {
  if (lookup.state === "idle") return <p className="-mt-2 text-xs text-muted">Kode diperiksa otomatis ke data pasar.</p>;
  if (lookup.state === "checking")
    return (
      <p className="-mt-2 flex items-center gap-1.5 text-xs text-muted" role="status">
        <Loader2 className="h-3.5 w-3.5 animate-spin" /> Memeriksa kode…
      </p>
    );
  if (lookup.state === "ok")
    return (
      <p className="-mt-2 flex items-center gap-1.5 text-xs text-income" role="status" data-testid="lookup-ok">
        <CheckCircle2 className="h-3.5 w-3.5 shrink-0" />
        <span className="min-w-0 truncate">
          {lookup.symbol}
          {lookup.name ? ` · ${lookup.name}` : ""}
          {lookup.price != null ? ` · ${fmtPrice(lookup.price)}` : ""}
        </span>
      </p>
    );
  if (lookup.state === "not_found")
    return (
      <p className="-mt-2 flex items-center gap-1.5 text-xs text-expense" role="status" data-testid="lookup-missing">
        <CircleAlert className="h-3.5 w-3.5 shrink-0" /> Kode {lookup.symbol} tidak ditemukan{kind === "stock" ? " di BEI" : ""}.
      </p>
    );
  if (lookup.state === "invalid")
    return (
      <p className="-mt-2 flex items-center gap-1.5 text-xs text-expense" role="status">
        <CircleAlert className="h-3.5 w-3.5 shrink-0" /> {lookup.error}
      </p>
    );
  return (
    <p className="-mt-2 flex items-center gap-1.5 text-xs text-amber-600" role="status">
      <CircleAlert className="h-3.5 w-3.5 shrink-0" /> Data pasar sedang tidak tersedia — aset tetap bisa ditambahkan.
    </p>
  );
}
