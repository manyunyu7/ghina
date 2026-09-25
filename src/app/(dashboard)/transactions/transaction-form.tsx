"use client";

import * as React from "react";
import type { Wallet, Category } from "@prisma/client";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Input, Textarea, Select, Field } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { MAX_TRANSACTION_PHOTOS } from "@/lib/photos";
import { createTransaction, updateTransaction } from "./actions";
import { PhotoField, initialPhotoItems, type PhotoItem } from "./photo-field";

export type TransactionFormData = {
  id: string;
  type: string;
  amount: number;
  walletId: string;
  toWalletId: string | null;
  categoryId: string | null;
  note: string | null;
  date: Date | string;
  /** Saved photo URLs, in display order. */
  photos?: string[];
};

const TYPES: { value: "expense" | "income" | "transfer"; label: string }[] = [
  { value: "expense", label: "Expense" },
  { value: "income", label: "Income" },
  { value: "transfer", label: "Transfer" },
];

function toDateInput(value: Date | string | undefined): string {
  const d = value ? new Date(value) : new Date();
  // YYYY-MM-DD in local time
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 10);
}

export function TransactionForm({
  open,
  onClose,
  wallets,
  categories,
  transaction,
}: {
  open: boolean;
  onClose: () => void;
  wallets: Wallet[];
  categories: Category[];
  transaction?: TransactionFormData;
}) {
  const isEdit = Boolean(transaction);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? "Edit transaction" : "Add transaction"}
      description={isEdit ? "Update the details of this transaction." : "Record a new income or expense."}
    >
      {/* Mount fresh each time the modal opens so local state initializes from props
          (no setState-in-effect needed). */}
      {open && (
        <TransactionFormBody
          wallets={wallets}
          categories={categories}
          transaction={transaction}
          onClose={onClose}
        />
      )}
    </Modal>
  );
}

function TransactionFormBody({
  wallets,
  categories,
  transaction,
  onClose,
}: {
  wallets: Wallet[];
  categories: Category[];
  transaction?: TransactionFormData;
  onClose: () => void;
}) {
  const isEdit = Boolean(transaction);
  // Balance adjustments are created from the wallet form; here they can only be edited
  // (signed amount, no category, type fixed).
  const isAdjustment = transaction?.type === "adjustment";
  const [type, setType] = React.useState<string>(transaction?.type ?? "expense");
  const [walletId, setWalletId] = React.useState<string>(transaction?.walletId ?? "");
  const [submitting, setSubmitting] = React.useState(false);
  const [photos, setPhotos] = React.useState<PhotoItem[]>(() => initialPhotoItems(transaction?.photos));
  const [photosBusy, setPhotosBusy] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  // Categories filtered by the chosen type. Transfers have no category list.
  const filteredCategories = React.useMemo(() => {
    if (type === "income") return categories.filter((c) => c.type === "income");
    if (type === "expense") return categories.filter((c) => c.type === "expense");
    return [];
  }, [categories, type]);

  // onSubmit (not `action`) so a failed save doesn't reset the fields React-19 style.
  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    await save(e.currentTarget, { withNewPhotos: true });
  }

  /**
   * Saves the form. `withNewPhotos: false` drops the not-yet-saved photos so a photo
   * problem never blocks the transaction itself (the user can add them again later).
   */
  async function save(form: HTMLFormElement, { withNewPhotos }: { withNewPhotos: boolean }) {
    if (submitting || photosBusy) return;
    const formData = new FormData(form);
    setSubmitting(true);
    setError(null);
    // Photos: kept URLs (edit) in order, then the new, already-compressed files.
    formData.delete("photos");
    formData.delete("keepPhotos");
    if (isEdit) {
      formData.set("photosManaged", "1");
      for (const p of photos) if (p.kind === "existing") formData.append("keepPhotos", p.url);
    }
    const newPhotos = withNewPhotos ? photos.filter((p) => p.kind === "new") : [];
    for (const p of newPhotos) if (p.kind === "new") formData.append("photos", p.file, p.file.name);
    try {
      if (isEdit) {
        await updateTransaction(formData);
      } else {
        await createTransaction(formData);
      }
      onClose();
    } catch (e) {
      setError(saveErrorMessage(e, newPhotos.length));
    } finally {
      setSubmitting(false);
    }
  }

  const hasNewPhotos = photos.some((p) => p.kind === "new");
  const formRef = React.useRef<HTMLFormElement>(null);

  return (
    <form ref={formRef} onSubmit={handleSubmit} className="space-y-4">
        {isEdit && transaction && <input type="hidden" name="id" value={transaction.id} />}

        {/* Type toggle */}
        {isAdjustment ? (
          <div className="rounded-lg border border-sky-200 bg-sky-50 p-3 text-sm text-slate-700">
            <p className="font-medium text-sky-700">Penyesuaian saldo</p>
            <p className="mt-0.5 text-xs">
              Jumlah bertanda: positif menambah saldo, negatif mengurangi. Hapus transaksi ini untuk
              mengembalikan saldo sebelumnya.
            </p>
            <input type="hidden" name="type" value="adjustment" />
          </div>
        ) : (
        <Field label="Type">
          <div className="grid grid-cols-3 gap-2">
            {TYPES.map((t) => (
              <button
                type="button"
                key={t.value}
                onClick={() => setType(t.value)}
                className={cn(
                  "h-10 rounded-lg border text-sm font-medium transition",
                  type === t.value
                    ? t.value === "income"
                      ? "border-income bg-income-soft text-income"
                      : t.value === "expense"
                        ? "border-expense bg-expense-soft text-expense"
                        : "border-primary bg-primary-soft text-primary"
                    : "border-border bg-surface text-muted hover:bg-accent",
                )}
              >
                {t.label}
              </button>
            ))}
          </div>
          <input type="hidden" name="type" value={type} />
        </Field>
        )}

        <Field label={isAdjustment ? "Selisih (+/−)" : "Amount"}>
          <Input
            name="amount"
            type="number"
            inputMode="decimal"
            step="any"
            min={isAdjustment ? undefined : "0"}
            required
            placeholder="0"
            defaultValue={transaction ? String(transaction.amount) : ""}
          />
        </Field>

        {/* The note sits right under the amount: it is what the list shows as the title. */}
        <Field label="Catatan (opsional)">
          <Textarea
            name="note"
            rows={2}
            maxLength={500}
            placeholder="Contoh: makan siang bareng tim"
            defaultValue={transaction?.note ?? ""}
          />
        </Field>

        <Field label={type === "transfer" ? "From wallet" : "Wallet"}>
          <Select
            name="walletId"
            required
            value={walletId}
            onChange={(e) => setWalletId(e.target.value)}
          >
            <option value="" disabled>
              Select a wallet
            </option>
            {wallets.map((w) => (
              <option key={w.id} value={w.id}>
                {w.name}
              </option>
            ))}
          </Select>
        </Field>

        {type === "transfer" && (
          <Field label="To wallet">
            <Select name="toWalletId" key={walletId} required defaultValue={transaction?.toWalletId ?? ""}>
              <option value="" disabled>
                Select destination
              </option>
              {wallets
                .filter((w) => w.id !== walletId)
                .map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.name}
                  </option>
                ))}
            </Select>
          </Field>
        )}

        {type !== "transfer" && !isAdjustment && (
          <Field label="Category">
            <Select
              name="categoryId"
              key={type}
              defaultValue={transaction?.categoryId ?? ""}
            >
              <option value="">Uncategorized</option>
              {filteredCategories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
        )}

        <Field label="Date">
          <Input name="date" type="date" required defaultValue={toDateInput(transaction?.date)} />
        </Field>

        <Field label={`Foto (maks ${MAX_TRANSACTION_PHOTOS})`}>
          <PhotoField items={photos} onChange={setPhotos} onBusyChange={setPhotosBusy} disabled={submitting} />
        </Field>

        {error && (
          <div role="alert" className="space-y-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
            <p>{error}</p>
            {hasNewPhotos && (
              <button
                type="button"
                className="font-medium underline underline-offset-2"
                disabled={submitting}
                onClick={() => formRef.current && save(formRef.current, { withNewPhotos: false })}
              >
                Simpan tanpa foto baru
              </button>
            )}
          </div>
        )}

        <div className="flex justify-end gap-2 pt-1">
          <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button type="submit" loading={submitting || photosBusy} disabled={wallets.length === 0}>
            {submitting ? "Menyimpan…" : photosBusy ? "Memproses foto…" : isEdit ? "Save changes" : "Add transaction"}
          </Button>
        </div>
    </form>
  );
}

/**
 * What to tell the user when saving failed. Production hides server error messages
 * (only the dev message or a digest arrives), and a proxy limit (HTTP 413) surfaces
 * as an "unexpected response", so photo trouble is also inferred from the request.
 */
export function saveErrorMessage(e: unknown, newPhotoCount: number): string {
  const msg = e instanceof Error ? e.message : "";
  if (/At most \d+ photos/.test(msg)) return "Maksimal 5 foto per transaksi.";
  if (/too large|terlalu besar|Body exceeded|413/i.test(msg)) {
    return "Foto terlalu besar untuk diunggah. Hapus atau ganti fotonya, atau simpan tanpa foto baru.";
  }
  if (/image file|bukan (file )?gambar|Unggah gambar/i.test(msg)) {
    return "Salah satu file bukan gambar yang didukung (JPEG, PNG, WebP, GIF, HEIC).";
  }
  if (newPhotoCount > 0) {
    return "Transaksi belum tersimpan: foto gagal diunggah. Coba lagi, atau simpan tanpa foto baru.";
  }
  return "Gagal menyimpan transaksi. Periksa isian lalu coba lagi.";
}
