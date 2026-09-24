"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { addDaysKey, focusAreas } from "@/lib/tasks";
import { formatDueDate, taskStatus, useLocalClock } from "./format";
import type { AreaDTO, TaskDTO } from "./types";
import { LinkPendingIcon } from "@/components/link-pending";

const MAX = 5;

/** Dashboard card: undone FIRE tasks of the focus areas (picked with the browser clock). */
export function FireTodayCard({ areas, tasks }: { areas: AreaDTO[]; tasks: TaskDTO[] }) {
  const clock = useLocalClock();
  // Like the board: when no area is in focus (all scheduled, none active) show every area.
  const picked = clock ? focusAreas(areas, clock) : areas;
  const focus = picked.length > 0 ? picked : areas;
  const ids = new Set(focus.map((a) => a.id));
  const byId = new Map(areas.map((a) => [a.id, a]));
  // FIRE = today/tomorrow: skip ones scheduled later (e.g. a recurring FIRE's next occurrence).
  const horizon = clock ? addDaysKey(clock.date, 1) : null;
  const list = tasks.filter((t) => ids.has(t.areaId) && (!t.dueDate || !horizon || t.dueDate <= horizon));
  const shown = list.slice(0, MAX);

  return (
    <Card>
      <CardHeader>
        <CardTitle>🔥 Tugas FIRE hari ini</CardTitle>
        <Link href="/tasks" className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline">
          Buka Tugas{" "}
          <LinkPendingIcon className="h-3.5 w-3.5">
            <ArrowRight className="h-3.5 w-3.5" />
          </LinkPendingIcon>
        </Link>
      </CardHeader>
      <CardContent>
        {focus.length > 0 && (
          <p className="-mt-2 mb-3 text-xs text-muted">Fokus: {focus.map((a) => a.name).join(", ")}</p>
        )}
        {shown.length === 0 ? (
          <p className="py-4 text-center text-sm text-muted">Tidak ada tugas FIRE di area fokus. Mantap! 🎉</p>
        ) : (
          <ul className="space-y-2">
            {shown.map((t) => {
              const area = byId.get(t.areaId);
              const { overdue } = taskStatus(t, clock);
              return (
                <li key={t.id} className="flex items-center gap-2 text-sm">
                  <span className="h-2 w-2 shrink-0 rounded-full bg-[#FF4B4B]" />
                  <span className="min-w-0 flex-1 truncate text-foreground">{t.title}</span>
                  {overdue && <span className="shrink-0 text-xs font-semibold text-expense">Terlambat</span>}
                  {t.dueDate && !overdue && (
                    <span className="shrink-0 text-xs text-muted">
                      {formatDueDate(t.dueDate, clock?.date ?? null)}
                      {t.dueTime && ` ${t.dueTime}`}
                    </span>
                  )}
                  {area && (
                    <span
                      className="shrink-0 rounded px-1 text-[10px] font-bold"
                      style={{ background: `${area.color}1f`, color: area.color }}
                    >
                      {area.code}
                    </span>
                  )}
                </li>
              );
            })}
            {list.length > MAX && <li className="pt-1 text-xs text-muted">+{list.length - MAX} lainnya</li>}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
