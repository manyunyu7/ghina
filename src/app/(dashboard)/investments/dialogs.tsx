"use client";

import * as React from "react";
import { AlertTriangle } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/input";
import { setManualPrice } from "./actions";
import { dateKeyWIB } from "./format";
import type { AssetDTO } from "./types";

/** Quick "update harga manual" for fund NAV, gold per gram, …. */
export function ManualPriceDialog({ asset, open, onClose }: { asset: AssetDTO; open: boolean; onClose: () => void }) {
  return (
    <Modal open={open} onClose={onClose} title={`Harga ${asset.symbol}`} description="Harga manual dipakai untuk menghitung nilai pasar.">
      {open && <ManualPriceForm asset={asset} onClose={onClose} />}
    </Modal>
  );
}

function ManualPriceForm({ asset, onClose }: { asset: AssetDTO; onClose: () => void }) {
  const [price, setPrice] = React.useState(asset.manualPrice != null ? String(asset.manualPrice) : "");
  const [date, setDate] = React.useState(dateKeyWIB());
  const [error, setError] = React.useState<string | null>(null);
  const [pending, startTransition] = React.useTransition();

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const p = Number(price);
    if (price.trim() === "" || !(Number.isFinite(p) && p >= 0)) return setError("Harga tidak valid");
    setError(null);
    startTransition(async () => {
      const r = await setManualPrice(asset.id, p, date);
      if (!r.ok) return setError(r.error);
      onClose();
    });
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="grid grid-cols-2 gap-3">
        <Field label={`Harga per ${asset.unit}`}>
          <Input type="number" inputMode="decimal" min={0} step="any" value={price} onChange={(e) => setPrice(e.target.value)} autoFocus aria-label="Harga baru" />
        </Field>
        <Field label="Per tanggal">
          <Input type="date" value={date} max={dateKeyWIB()} onChange={(e) => setDate(e.target.value)} aria-label="Tanggal harga" />
        </Field>
      </div>
      {asset.priceMode === "auto" && <p className="text-xs text-amber-600">Aset ini akan beralih ke harga manual.</p>}
      {error && <p className="text-sm text-expense" role="alert">{error}</p>}
      <div className="flex justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
          Batal
        </Button>
        <Button type="submit" loading={pending}>
          {pending ? "Menyimpan…" : "Simpan harga"}
        </Button>
      </div>
    </form>
  );
}

/** A destructive confirmation with a warning box and an optional safer alternative. */
export function ConfirmDialog({
  open,
  onClose,
  title,
  children,
  confirmLabel,
  onConfirm,
  alternative,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  confirmLabel: string;
  onConfirm: () => Promise<{ ok: true } | { ok: false; error: string }>;
  alternative?: { label: string; run: () => Promise<{ ok: true } | { ok: false; error: string }> };
}) {
  const [pending, startTransition] = React.useTransition();
  const [which, setWhich] = React.useState<"main" | "alt" | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  function run(kind: "main" | "alt", fn: () => Promise<{ ok: true } | { ok: false; error: string }>) {
    setError(null);
    setWhich(kind);
    startTransition(async () => {
      const r = await fn().catch(() => ({ ok: false as const, error: "Terjadi kesalahan, coba lagi" }));
      if (!r.ok) setError(r.error);
      else onClose();
    });
  }

  return (
    <Modal open={open} onClose={pending ? () => {} : onClose} title={title}>
      <div className="space-y-4">
        <div className="flex gap-3 rounded-lg bg-expense-soft p-3 text-expense">
          <AlertTriangle className="h-5 w-5 shrink-0" />
          <div className="space-y-1 text-sm">{children}</div>
        </div>
        {error && <p className="text-sm text-expense" role="alert">{error}</p>}
        <div className="flex flex-wrap justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={pending}>
            Batal
          </Button>
          {alternative && (
            <Button variant="outline" onClick={() => run("alt", alternative.run)} loading={pending && which === "alt"} disabled={pending}>
              {alternative.label}
            </Button>
          )}
          <Button variant="danger" onClick={() => run("main", onConfirm)} loading={pending && which === "main"} disabled={pending}>
            {pending && which === "main" ? "Menghapus…" : confirmLabel}
          </Button>
        </div>
      </div>
    </Modal>
  );
}
