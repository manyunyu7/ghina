"use client";

import * as React from "react";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { AlarmClock, Check, Clock, MoveRight, Repeat, StickyNote, Wallet } from "lucide-react";
import { MEPET_LABEL, OVERDUE_COLOR, OVERDUE_LABEL, bucketInfo, type LocalClock } from "@/lib/tasks";
import { cn } from "@/lib/utils";
import { formatDueDate, recurrenceLabel, taskStatus } from "./format";
import type { AreaDTO, TaskDTO } from "./types";
import { Money } from "@/components/money/money";

type CardProps = {
  task: TaskDTO;
  clock: LocalClock | null;
  currency: string;
  /** Shown as a small chip when the card is outside its area column (filters, dashboard). */
  area?: AreaDTO;
  onCheck?: (task: TaskDTO) => void;
  onOpen?: (task: TaskDTO) => void;
  onMove?: (task: TaskDTO) => void;
  className?: string;
  overlay?: boolean;
};

export function TaskCardBody({
  task,
  clock,
  currency,
  area,
  onCheck,
  onOpen,
  onMove,
  className,
  overlay,
  ref,
  ...rest
}: CardProps & React.HTMLAttributes<HTMLDivElement> & { ref?: React.Ref<HTMLDivElement> }) {
  const { overdue, mepet } = taskStatus(task, clock);
  const bucket = bucketInfo(task.bucket);
  const pending = task.id.startsWith("tmp-");
  const accent = overdue ? OVERDUE_COLOR : mepet ? bucketInfo("fire").color : null;

  return (
    <div
      ref={ref}
      {...rest}
      className={cn(
        "group relative flex items-start gap-2 rounded-xl border border-border bg-card p-2.5 text-left shadow-sm transition",
        "outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
        overlay && "rotate-1 cursor-grabbing shadow-lg ring-2 ring-primary/30",
        pending && "opacity-60",
        className,
      )}
      style={{ ...rest.style, borderLeftColor: accent ?? bucket.color, borderLeftWidth: 3 }}
    >
      <button
        type="button"
        onClick={() => onCheck?.(task)}
        disabled={pending || !onCheck}
        aria-label={task.done ? `Tandai belum selesai: ${task.title}` : `Tandai selesai: ${task.title}`}
        className={cn(
          "mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-md border-2 transition",
          task.done ? "border-income bg-income text-white" : "border-muted-soft hover:border-income hover:bg-income-soft",
        )}
      >
        {task.done && <Check className="h-3.5 w-3.5" strokeWidth={3} />}
      </button>

      <div className="min-w-0 flex-1">
        <button
          type="button"
          onClick={() => onOpen?.(task)}
          disabled={!onOpen || pending}
          className={cn(
            "block w-full text-left text-sm font-medium leading-snug text-foreground [overflow-wrap:anywhere]",
            onOpen && "hover:text-primary",
            task.done && "text-muted line-through",
          )}
        >
          {task.title}
        </button>

        <div className="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-muted">
          {overdue && (
            <span className="rounded-full px-1.5 py-px text-[11px] font-semibold text-white" style={{ background: OVERDUE_COLOR }}>
              {OVERDUE_LABEL}
            </span>
          )}
          {mepet && (
            <span
              className="rounded-full px-1.5 py-px text-[11px] font-semibold"
              style={{ background: `${bucketInfo("fire").color}1f`, color: bucketInfo("fire").color }}
            >
              🔥 {MEPET_LABEL}
            </span>
          )}
          {area && (
            <span
              className="rounded-full px-1.5 py-px text-[11px] font-semibold"
              style={{ background: `${area.color}1f`, color: area.color }}
            >
              {area.code}
            </span>
          )}
          {task.dueDate && (
            <span className={cn("inline-flex items-center gap-0.5", overdue && "font-medium text-expense")}>
              <Clock className="h-3 w-3" />
              {formatDueDate(task.dueDate, clock?.date ?? null)}
              {task.dueTime && ` · ${task.dueTime}`}
            </span>
          )}
          {task.remindBefore != null && task.dueTime && (
            <AlarmClock className="h-3 w-3" aria-label="Ada pengingat" />
          )}
          {task.recurrence && (
            <span className="inline-flex items-center" title={recurrenceLabel(task.recurrence)}>
              <Repeat className="h-3 w-3" aria-label={recurrenceLabel(task.recurrence)} />
            </span>
          )}
          {task.note && <StickyNote className="h-3 w-3" aria-label="Ada catatan" />}
          {task.amount != null && (
            <span className="inline-flex items-center gap-0.5 rounded-full bg-income-soft px-1.5 py-px text-[11px] font-medium text-income">
              <Wallet className="h-3 w-3" />
              <Money amount={task.amount} currency={currency} />
              {task.transactionId && <Check className="h-3 w-3" aria-label="Pengeluaran tercatat" />}
            </span>
          )}
        </div>
      </div>

      {onMove && !pending && (
        <button
          type="button"
          onClick={() => onMove(task)}
          aria-label={`Pindah ke… ${task.title}`}
          title="Pindah ke…"
          className="-mr-1 -mt-0.5 shrink-0 rounded-md p-1 text-muted-soft opacity-100 transition hover:bg-accent hover:text-foreground focus-visible:opacity-100 sm:opacity-0 sm:group-hover:opacity-100"
        >
          <MoveRight className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}

/** A board card that can be dragged within / between cells. */
export function SortableTaskCard(props: CardProps & { dragDisabled?: boolean }) {
  const { dragDisabled, ...cardProps } = props;
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: props.task.id,
    disabled: dragDisabled || props.task.id.startsWith("tmp-"),
  });

  // Keyboard dragging only when the card itself is focused (Enter/Space on the inner
  // buttons must keep toggling / opening).
  const onKeyDown = listeners?.onKeyDown as ((e: React.KeyboardEvent) => void) | undefined;
  const safeListeners = {
    ...listeners,
    onKeyDown: (e: React.KeyboardEvent) => {
      if (e.target === e.currentTarget) onKeyDown?.(e);
    },
  };

  return (
    <TaskCardBody
      ref={setNodeRef}
      {...cardProps}
      {...attributes}
      {...(dragDisabled ? {} : safeListeners)}
      role="group"
      aria-label={props.task.title}
      aria-roledescription="tugas yang bisa dipindah"
      className={cn(!dragDisabled && "cursor-grab touch-manipulation", isDragging && "opacity-40")}
      style={{ transform: CSS.Translate.toString(transform), transition }}
    />
  );
}
