"use client";

import * as React from "react";
import { ArrowDown, ArrowUp, Wallet } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Label, Select } from "@/components/ui/input";
import { BUCKETS, type BucketId } from "@/lib/tasks";
import { cn, formatCurrency } from "@/lib/utils";
import type { AreaDTO, TaskDTO, WalletOption } from "./types";

/** "Catat pengeluaran Rp X?" when completing a task with an amount. */
export function CompleteExpenseDialog({
  task,
  wallets,
  currency,
  onClose,
  onConfirm,
}: {
  task: TaskDTO | null;
  wallets: WalletOption[];
  currency: string;
  onClose: () => void;
  /** walletId = null → complete without recording an expense. */
  onConfirm: (task: TaskDTO, record: { walletId: string } | null) => void;
}) {
  return (
    <Modal open={!!task} onClose={onClose} title="Tugas selesai 🎉">
      {task && <CompleteExpenseBody key={task.id} task={task} wallets={wallets} currency={currency} onConfirm={onConfirm} />}
    </Modal>
  );
}

function CompleteExpenseBody({
  task,
  wallets,
  currency,
  onConfirm,
}: {
  task: TaskDTO;
  wallets: WalletOption[];
  currency: string;
  onConfirm: (task: TaskDTO, record: { walletId: string } | null) => void;
}) {
  const known = task.walletId && wallets.some((w) => w.id === task.walletId);
  const [walletId, setWalletId] = React.useState(known ? task.walletId! : (wallets[0]?.id ?? ""));
  const amount = formatCurrency(task.amount ?? 0, currency);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3 rounded-xl bg-income-soft p-3 text-income">
        <Wallet className="h-5 w-5 shrink-0" />
        <p className="text-sm font-medium">
          Catat pengeluaran <span className="font-bold">{amount}</span>?
        </p>
      </div>
      <p className="text-sm text-muted">
        Pengeluaran &ldquo;{task.title}&rdquo; dicatat dengan tanggal hari ini.
      </p>
      {!known &&
        (wallets.length > 0 ? (
          <Field label="Dari dompet">
            <Select value={walletId} onChange={(e) => setWalletId(e.target.value)}>
              {wallets.map((w) => (
                <option key={w.id} value={w.id}>
                  {w.name}
                </option>
              ))}
            </Select>
          </Field>
        ) : (
          <p className="text-sm text-expense">Belum ada dompet — buat dompet dulu untuk mencatat pengeluaran.</p>
        ))}
      <div className="flex justify-end gap-2">
        <Button variant="ghost" onClick={() => onConfirm(task, null)}>
          Tidak
        </Button>
        <Button onClick={() => onConfirm(task, { walletId })} disabled={!walletId} autoFocus>
          Ya, catat
        </Button>
      </div>
    </div>
  );
}

/** Un-completing a task that recorded an expense: keep or delete the expense. */
export function UncompleteDialog({
  task,
  currency,
  onClose,
  onConfirm,
}: {
  task: TaskDTO | null;
  currency: string;
  onClose: () => void;
  onConfirm: (task: TaskDTO, deleteExpense: boolean) => void;
}) {
  return (
    <Modal open={!!task} onClose={onClose} title="Batalkan selesai?">
      {task && (
        <div className="space-y-4">
          <p className="text-sm text-muted">
            Tugas &ldquo;{task.title}&rdquo; sudah mencatat pengeluaran
            {task.amount != null && <span className="font-semibold text-foreground"> {formatCurrency(task.amount, currency)}</span>}.
            Hapus juga pengeluarannya (saldo dompet dikembalikan)?
          </p>
          <div className="flex flex-wrap justify-end gap-2">
            <Button variant="ghost" onClick={onClose}>
              Batal
            </Button>
            <Button variant="outline" onClick={() => onConfirm(task, false)}>
              Biarkan pengeluaran
            </Button>
            <Button variant="danger" onClick={() => onConfirm(task, true)}>
              Hapus pengeluaran
            </Button>
          </div>
        </div>
      )}
    </Modal>
  );
}

/** Keyboard/touch alternative to drag & drop: pick area + bucket, or nudge within the cell. */
export function MoveDialog({
  task,
  areas,
  position,
  onClose,
  onMove,
  onNudge,
}: {
  task: TaskDTO | null;
  areas: AreaDTO[];
  /** Index of the task in its cell and the cell size. */
  position: { index: number; size: number } | null;
  onClose: () => void;
  onMove: (task: TaskDTO, to: { areaId: string; bucket: BucketId }) => void;
  onNudge: (task: TaskDTO, dir: -1 | 1) => void;
}) {
  return (
    <Modal open={!!task} onClose={onClose} title="Pindah ke…" description={task?.title}>
      {task && <MoveBody key={task.id} task={task} areas={areas} position={position} onMove={onMove} onNudge={onNudge} />}
    </Modal>
  );
}

function MoveBody({
  task,
  areas,
  position,
  onMove,
  onNudge,
}: {
  task: TaskDTO;
  areas: AreaDTO[];
  position: { index: number; size: number } | null;
  onMove: (task: TaskDTO, to: { areaId: string; bucket: BucketId }) => void;
  onNudge: (task: TaskDTO, dir: -1 | 1) => void;
}) {
  const [areaId, setAreaId] = React.useState(task.areaId);
  const live = areas.filter((a) => !a.archived || a.id === task.areaId);

  return (
    <div className="space-y-4">
      <Field label="Area">
        <Select value={areaId} onChange={(e) => setAreaId(e.target.value)}>
          {live.map((a) => (
            <option key={a.id} value={a.id}>
              {a.name} ({a.code})
            </option>
          ))}
        </Select>
      </Field>
      <div>
        <Label>Pindah ke prioritas</Label>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          {BUCKETS.map((b) => {
            const same = areaId === task.areaId && b.id === task.bucket;
            return (
              <Button
                key={b.id}
                variant="outline"
                disabled={same}
                onClick={() => onMove(task, { areaId, bucket: b.id })}
                className={cn("justify-start", same && "opacity-60")}
                style={{ borderColor: b.color }}
              >
                {b.emoji} {b.label}
                {same && <span className="text-xs text-muted">(sekarang)</span>}
              </Button>
            );
          })}
        </div>
      </div>
      {position && position.size > 1 && (
        <div>
          <Label>Urutan di sel ini</Label>
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" disabled={position.index === 0} onClick={() => onNudge(task, -1)}>
              <ArrowUp className="h-4 w-4" /> Naik
            </Button>
            <Button
              variant="secondary"
              size="sm"
              disabled={position.index >= position.size - 1}
              onClick={() => onNudge(task, 1)}
            >
              <ArrowDown className="h-4 w-4" /> Turun
            </Button>
            <span className="self-center text-xs text-muted">
              {position.index + 1} dari {position.size}
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
