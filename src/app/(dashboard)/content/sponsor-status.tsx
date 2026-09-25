"use client";

import * as React from "react";
import Link from "next/link";
import { BadgeCheck, CircleDollarSign } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/input";
import { sponsorTransactionNote } from "@/lib/content";
import { cn, formatCurrency } from "@/lib/utils";
import { markSponsorPaid, markSponsorUnpaid } from "./actions";
import { usePlanner } from "./planner";
import { formatDateKey, useToast } from "./ui";
import type { ContentItemDTO } from "./types";
import { LinkPending } from "@/components/link-pending";
import { Money } from "@/components/money/money";

const todayKey = () => {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
};

/**
 * Paid / unpaid state of a saved sponsor. "Tandai dibayar" can record an income
 * transaction (wallet picker) through `markSponsorPaid`; "Tandai belum dibayar" can
 * delete that transaction again (reversing the wallet balance).
 */
export function SponsorStatus({ item, dirty }: { item: ContentItemDTO; dirty: boolean }) {
  const { data, mutate } = usePlanner();
  const toast = useToast();
  const s = item.sponsor!;
  const [panel, setPanel] = React.useState<null | "pay" | "unpay">(null);
  const barter = s.amount === 0;
  const [record, setRecord] = React.useState(!barter && data.wallets.length > 0);
  const [walletId, setWalletId] = React.useState(data.wallets[0]?.id ?? "");
  const [amount, setAmount] = React.useState(String(s.amount || ""));
  const [categoryId, setCategoryId] = React.useState("");
  const [date, setDate] = React.useState(todayKey);
  const [note, setNote] = React.useState(sponsorTransactionNote(s.brand));
  const [deleteTx, setDeleteTx] = React.useState(true);
  const [busy, setBusy] = React.useState(false);

  const overdue = !s.paid && !!s.due && s.due < todayKey();

  // Rendered inside the item form: no nested <form>; Enter must not save the item.
  const noSubmit = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && (e.target as HTMLElement).tagName === "INPUT") e.preventDefault();
  };

  function pay() {
    const amt = Number(amount);
    if (record) {
      if (!walletId) return toast({ text: "Pilih dompet", tone: "error" });
      if (!Number.isFinite(amt) || amt <= 0) return toast({ text: "Nominal harus lebih dari 0", tone: "error" });
    }
    // A cleared date input gives NaN — toISOString() would throw and leave `busy` stuck.
    const [y, m, d] = date.split("-").map(Number);
    const local = new Date(y, m - 1, d, 12);
    if (record && Number.isNaN(local.getTime())) return toast({ text: "Isi tanggal", tone: "error" });
    const at = Number.isNaN(local.getTime()) ? undefined : local.toISOString();
    setBusy(true);
    mutate(
      null,
      async () => {
        try {
          return await markSponsorPaid(item.id, record ? { walletId, amount: amt, categoryId: categoryId || null, date: at, note: note.trim() || undefined } : null);
        } finally {
          setBusy(false);
        }
      },
      (r) => {
        setPanel(null);
        toast({ text: r.transactionId && record ? "Lunas ✓ — pemasukan dicatat" : "Ditandai lunas ✓", tone: "success" });
      },
    );
  }

  function unpay() {
    setBusy(true);
    mutate(
      null,
      async () => {
        try {
          return await markSponsorUnpaid(item.id, { deleteTransaction: !!s.transactionId && deleteTx });
        } finally {
          setBusy(false);
        }
      },
      () => {
        setPanel(null);
        toast({ text: s.transactionId && deleteTx ? "Belum dibayar — transaksi pemasukan dihapus" : "Ditandai belum dibayar", tone: "info" });
      },
    );
  }

  return (
    <div className="mt-3 border-t border-border pt-3">
      <div className="flex flex-wrap items-center gap-2">
        <span
          className={cn(
            "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold",
            s.paid ? "bg-income-soft text-income" : overdue ? "bg-expense-soft text-expense" : "bg-amber-100 text-amber-800",
          )}
        >
          {s.paid ? <BadgeCheck className="h-3.5 w-3.5" /> : <CircleDollarSign className="h-3.5 w-3.5" />}
          {s.paid ? "Lunas" : overdue ? "Lewat jatuh tempo" : "Belum dibayar"}
        </span>
        <span className="text-sm text-foreground">
          {s.brand} · {barter ? "Barter" : <Money amount={s.amount} currency={s.currency} />}
          {s.due && !s.paid && <span className="text-muted"> · jatuh tempo {formatDateKey(s.due)}</span>}
        </span>
        {s.paid && s.transactionId && (
          <Link href="/transactions" className="text-xs font-medium text-primary hover:underline">
            Lihat transaksi
            <LinkPending spinner={false} />
          </Link>
        )}
        <div className="ml-auto">
          {dirty ? (
            <span className="text-xs text-muted">Simpan perubahan dulu</span>
          ) : s.paid ? (
            <Button type="button" variant="outline" size="sm" onClick={() => setPanel(panel ? null : "unpay")}>
              Tandai belum dibayar
            </Button>
          ) : (
            <Button type="button" size="sm" onClick={() => setPanel(panel ? null : "pay")}>
              Tandai dibayar
            </Button>
          )}
        </div>
      </div>

      {panel === "pay" && !dirty && (
        <div onKeyDown={noSubmit} className="mt-3 space-y-3 rounded-lg bg-accent/60 p-3">
          <label className="flex items-center gap-2 text-sm text-foreground">
            <input type="checkbox" checked={record} onChange={(e) => setRecord(e.target.checked)} className="h-4 w-4 accent-[var(--color-primary)]" disabled={data.wallets.length === 0} />
            Catat sebagai pemasukan di dompet
          </label>
          {data.wallets.length === 0 && (
            <p className="text-xs text-muted">
              Belum ada dompet. <Link href="/wallets" className="text-primary hover:underline">Buat dompet<LinkPending spinner={false} /></Link> untuk mencatat pemasukan.
            </p>
          )}
          {record && (
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Field label="Dompet">
                <Select aria-label="Dompet" value={walletId} onChange={(e) => setWalletId(e.target.value)}>
                  {data.wallets.map((w) => (
                    <option key={w.id} value={w.id}>
                      {w.name} ({formatCurrency(w.balance, w.currency)})
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Nominal diterima">
                <Input type="number" min={0} step="any" value={amount} onChange={(e) => setAmount(e.target.value)} />
              </Field>
              <Field label="Kategori (opsional)">
                <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
                  <option value="">Tanpa kategori</option>
                  {data.incomeCategories.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Tanggal">
                <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
              </Field>
              <Field label="Catatan" className="sm:col-span-2">
                <Input value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} />
              </Field>
            </div>
          )}
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" size="sm" onClick={() => setPanel(null)}>
              Batal
            </Button>
            <Button type="button" size="sm" loading={busy} onClick={pay}>
              {busy ? "Menyimpan…" : record ? "Tandai lunas & catat" : "Tandai lunas"}
            </Button>
          </div>
        </div>
      )}

      {panel === "unpay" && !dirty && (
        <div className="mt-3 space-y-3 rounded-lg bg-accent/60 p-3">
          {s.transactionId ? (
            <label className="flex items-start gap-2 text-sm text-foreground">
              <input type="checkbox" checked={deleteTx} onChange={(e) => setDeleteTx(e.target.checked)} className="mt-0.5 h-4 w-4 accent-[var(--color-primary)]" />
              <span>
                Hapus juga transaksi pemasukannya
                <span className="block text-xs text-muted">Saldo dompet dikembalikan. Jika tidak dicentang, transaksi tetap ada tetapi tidak lagi ditautkan.</span>
              </span>
            </label>
          ) : (
            <p className="text-sm text-muted">Tidak ada transaksi yang tertaut.</p>
          )}
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" size="sm" onClick={() => setPanel(null)}>
              Batal
            </Button>
            <Button type="button" variant={s.transactionId && deleteTx ? "danger" : "primary"} size="sm" onClick={unpay} loading={busy}>
              {busy ? "Menyimpan…" : "Tandai belum dibayar"}
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
