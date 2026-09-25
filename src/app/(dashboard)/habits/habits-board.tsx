"use client";

import * as React from "react";
import Link from "next/link";
import { Archive, Eye, EyeOff, Plus, ShieldCheck, Sprout } from "lucide-react";
import { Button } from "@/components/ui/button";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { LinkPending } from "@/components/link-pending";
import type { HabitOverviewItem } from "@/lib/habits-server";
import { cn } from "@/lib/utils";
import { HabitCard } from "./habit-card";
import { HabitFormDialog, type HabitFormTarget } from "./habit-form";
import { formatLongDate } from "./format";
import { useBlurNames, useBrowserToday } from "./hooks";

export function HabitsBoard({
  habits,
  today,
  canSkip,
  showArchived,
}: {
  habits: HabitOverviewItem[];
  today: string;
  /** habitId → whether a rest day is still allowed today. */
  canSkip: Record<string, boolean>;
  showArchived: boolean;
}) {
  useBrowserToday(today);
  const [blur, setBlur] = useBlurNames();
  const [form, setForm] = React.useState<HabitFormTarget | null>(null);

  const active = habits.filter((h) => !h.archived);
  const archived = habits.filter((h) => h.archived);
  const build = active.filter((h) => h.kind !== "quit");
  const quit = active.filter((h) => h.kind === "quit");
  const due = build.filter((h) => h.today.scheduled || h.today.met);
  const metCount = due.filter((h) => h.today.met).length;

  const card = (h: HabitOverviewItem) => (
    <HabitCard key={h.id} item={h} today={today} canSkipToday={canSkip[h.id] ?? true} blur={blur} onEdit={() => setForm({ mode: "edit", habit: h })} />
  );

  return (
    <div>
      <PageHeader
        title="Kebiasaan"
        description={`Teman Streak · ${formatLongDate(today)}`}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => setBlur(!blur)}
              aria-pressed={blur}
              title="Samarkan nama kebiasaan di layar ini (disimpan di browser ini)"
            >
              {blur ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              {blur ? "Nama disamarkan" : "Samarkan nama"}
            </Button>
            <Button variant="outline" onClick={() => setForm({ mode: "create", kind: "quit" })}>
              <ShieldCheck className="h-4 w-4" /> Berhenti
            </Button>
            <Button onClick={() => setForm({ mode: "create", kind: "build" })}>
              <Plus className="h-4 w-4" /> Kebiasaan
            </Button>
          </div>
        }
      />

      {active.length === 0 ? (
        <EmptyState
          icon={Sprout}
          title="Belum ada kebiasaan"
          description="Mulai satu kebiasaan kecil (minum air, baca buku) atau lepas dari yang ingin kamu tinggalkan. Pelan-pelan, satu hari setiap kali."
          action={
            <div className="flex flex-wrap justify-center gap-2">
              <Button onClick={() => setForm({ mode: "create", kind: "build" })}>
                <Plus className="h-4 w-4" /> Bangun kebiasaan
              </Button>
              <Button variant="outline" onClick={() => setForm({ mode: "create", kind: "quit" })}>
                <ShieldCheck className="h-4 w-4" /> Berhenti dari kebiasaan
              </Button>
            </div>
          }
        />
      ) : (
        <div className="space-y-8">
          {build.length > 0 && (
            <section>
              <div className="mb-3 flex items-end justify-between gap-3">
                <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Membangun</h2>
                {due.length > 0 && (
                  <p className="text-sm text-muted">
                    <b className="text-foreground">
                      {metCount}/{due.length}
                    </b>{" "}
                    tercapai hari ini{metCount === due.length && " 🎉"}
                  </p>
                )}
              </div>
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">{build.map(card)}</div>
            </section>
          )}
          {quit.length > 0 && (
            <section>
              <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted">Berhenti</h2>
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">{quit.map(card)}</div>
            </section>
          )}
        </div>
      )}

      <div className="mt-8">
        <Link
          href={showArchived ? "/habits" : "/habits?arsip=1"}
          scroll={false}
          className="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-foreground"
        >
          <Archive className="h-4 w-4" /> {showArchived ? "Sembunyikan arsip" : "Lihat arsip"}
          <LinkPending />
        </Link>
        {showArchived && (
          <div className="mt-3">
            {archived.length === 0 ? (
              <p className="text-sm text-muted">Belum ada kebiasaan yang diarsipkan.</p>
            ) : (
              <ul className="divide-y divide-border rounded-card border border-border bg-card">
                {archived.map((h) => (
                  <li key={h.id} className="flex items-center gap-3 px-4 py-3">
                    <span aria-hidden className="text-lg">
                      {h.emoji || "•"}
                    </span>
                    <Link
                      href={`/habits/${h.id}`}
                      className={cn("min-w-0 flex-1 truncate text-sm font-medium hover:text-primary", blur && "blur-[6px] hover:blur-none")}
                    >
                      {h.name}
                    </Link>
                    <Button variant="ghost" size="sm" onClick={() => setForm({ mode: "edit", habit: h })}>
                      Kelola
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </div>

      <HabitFormDialog target={form} today={today} onClose={() => setForm(null)} />
    </div>
  );
}
