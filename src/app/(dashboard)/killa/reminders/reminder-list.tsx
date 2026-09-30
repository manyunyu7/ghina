"use client";

import * as React from "react";
import { AlertTriangle, BellRing, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import type { KillaReminder } from "@/lib/killa";
import { cancelKillaReminder } from "../actions";

const dateFmt = new Intl.DateTimeFormat("id-ID", {
  weekday: "short",
  day: "numeric",
  month: "short",
  hour: "2-digit",
  minute: "2-digit",
});

/** Reminder rows; "Batalkan" removes one (it may already have fired — then it just disappears). */
export function ReminderList({ reminders }: { reminders: KillaReminder[] }) {
  const [gone, setGone] = React.useState<Set<number>>(new Set());
  const [busy, setBusy] = React.useState<number | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  async function cancel(r: KillaReminder) {
    if (!window.confirm(`Batalkan pengingat “${r.text}”?`)) return;
    setError(null);
    setBusy(r.id);
    const res = await cancelKillaReminder(r.id).catch(() => ({ ok: false as const, error: "Terjadi kesalahan, coba lagi" }));
    setBusy(null);
    if (!res.ok) setError(res.error);
    else setGone((g) => new Set(g).add(r.id));
  }

  const shown = reminders.filter((r) => !gone.has(r.id));
  return (
    <div className="space-y-3">
      {error && (
        <div role="alert" className="flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}
      <Card className="divide-y divide-border-soft overflow-hidden">
        {shown.length === 0 ? (
          <p className="px-4 py-6 text-center text-sm text-muted">Semua pengingat sudah dibatalkan.</p>
        ) : (
          shown.map((r) => (
            <div key={r.id} className="flex items-start gap-3 px-4 py-3">
              <BellRing className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
              <div className="min-w-0 flex-1">
                <p className="break-words text-sm font-medium text-foreground">{r.text || "(tanpa teks)"}</p>
                <p className="mt-0.5 text-xs text-muted">
                  {r.nextAt ? dateFmt.format(new Date(r.nextAt)) : "—"} · <code className="font-mono">{r.spec}</code> · #{r.id}
                </p>
              </div>
              <Button variant="ghost" size="sm" onClick={() => cancel(r)} loading={busy === r.id} disabled={busy !== null}>
                {busy !== r.id && <X className="h-4 w-4" />} Batalkan
              </Button>
            </div>
          ))
        )}
      </Card>
    </div>
  );
}
