"use client";

import * as React from "react";
import Link from "next/link";
import {
  DndContext,
  DragOverlay,
  KeyboardSensor,
  PointerSensor,
  TouchSensor,
  closestCorners,
  pointerWithin,
  useDroppable,
  useSensor,
  useSensors,
  type CollisionDetection,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
  type UniqueIdentifier,
} from "@dnd-kit/core";
import { SortableContext, arrayMove, sortableKeyboardCoordinates, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { CheckCircle2, ChevronLeft, ChevronRight, ListTodo, Plus, Settings2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { SavingHint } from "@/components/ui/saving-hint";
import { CategoryIcon } from "@/components/icon";
import {
  BUCKETS,
  compareTasks,
  focusAreas,
  isMepet,
  isOverdue,
  nextOccurrence,
  type BucketId,
  type LocalClock,
} from "@/lib/tasks";
import { cn } from "@/lib/utils";
import {
  completeTask,
  createTask,
  moveTask,
  reorderTasks,
  uncompleteTask,
  type TaskActionResult,
} from "./actions";
import { errorText, formatDoneAt, formatDueDate, useLocalClock } from "./format";
import { SortableTaskCard, TaskCardBody } from "./task-card";
import { TaskDialog, type TaskDialogTarget } from "./task-dialog";
import { CompleteExpenseDialog, MoveDialog, UncompleteDialog } from "./task-dialogs";
import { scheduleLabel } from "./schedule";
import type { AreaDTO, BoardData, TaskDTO } from "./types";
import { LinkPendingIcon } from "@/components/link-pending";

type State = { open: TaskDTO[]; done: TaskDTO[] };
type Filter = null | "today" | "mepet" | "overdue" | "done";
type Cell = { areaId: string; bucket: BucketId };

const cellKey = (areaId: string, bucket: string) => `${areaId}|${bucket}`;
const parseCell = (key: string): Cell => {
  const i = key.lastIndexOf("|");
  return { areaId: key.slice(0, i), bucket: key.slice(i + 1) as BucketId };
};
const DROP_PREFIX = "cell:";
const isCellId = (id: UniqueIdentifier) => String(id).startsWith(DROP_PREFIX);

/** Pointer inside a cell/card first (mouse & touch), closest corners otherwise (keyboard). */
const collision: CollisionDetection = (args) => {
  const hits = pointerWithin(args);
  if (hits.length > 0) {
    // Prefer a card over the cell that contains it.
    const card = hits.find((h) => !isCellId(h.id));
    return card ? [card] : hits;
  }
  return closestCorners(args);
};

/**
 * Mouse/pen dragging through pointer events: dnd-kit then listens on the pressed element
 * itself, which keeps receiving the events after the card moves to another cell (a
 * document `mouseup` is lost once the pressed node is re-mounted). Touch goes through
 * TouchSensor (long-press) so swiping still scrolls the board.
 */
class MousePointerSensor extends PointerSensor {
  static activators = [
    {
      eventName: "onPointerDown" as const,
      handler: ({ nativeEvent: e }: React.PointerEvent) => e.isPrimary && e.button === 0 && e.pointerType !== "touch",
    },
  ];
}

// ---------- Toasts ----------

type Toast = { id: number; text: string; tone: "success" | "error" | "info"; action?: { label: string; run: () => void } };

function useToasts() {
  const [toasts, setToasts] = React.useState<Toast[]>([]);
  const seq = React.useRef(0);
  const dismiss = React.useCallback((id: number) => setToasts((t) => t.filter((x) => x.id !== id)), []);
  const push = React.useCallback(
    (t: Omit<Toast, "id">) => {
      const id = ++seq.current;
      setToasts((prev) => [...prev.slice(-2), { ...t, id }]);
      setTimeout(() => dismiss(id), t.action ? 7000 : 4500);
    },
    [dismiss],
  );
  return { toasts, push, dismiss };
}

function Toasts({ toasts, dismiss }: { toasts: Toast[]; dismiss: (id: number) => void }) {
  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-4 z-[60] flex flex-col items-center gap-2 px-4" aria-live="polite">
      {toasts.map((t) => (
        <div
          key={t.id}
          role={t.tone === "error" ? "alert" : "status"}
          className={cn(
            "pointer-events-auto flex w-full max-w-sm items-center gap-3 rounded-xl px-4 py-3 text-sm font-medium text-white shadow-lg animate-fade-in",
            t.tone === "error" ? "bg-expense" : t.tone === "success" ? "bg-slate-900" : "bg-slate-700",
          )}
        >
          <span className="min-w-0 flex-1">{t.text}</span>
          {t.action && (
            <button
              type="button"
              className="shrink-0 font-semibold text-primary-soft underline-offset-2 hover:underline"
              onClick={() => {
                t.action!.run();
                dismiss(t.id);
              }}
            >
              {t.action.label}
            </button>
          )}
          <button type="button" aria-label="Tutup" onClick={() => dismiss(t.id)} className="shrink-0 opacity-70 hover:opacity-100">
            <X className="h-4 w-4" />
          </button>
        </div>
      ))}
    </div>
  );
}

// ---------- Board ----------

export function TaskBoard({ data }: { data: BoardData }) {
  const clock = useLocalClock();
  const base = React.useMemo<State>(() => ({ open: data.tasks, done: data.doneTasks }), [data.tasks, data.doneTasks]);
  const [state, addOptimistic] = React.useOptimistic(base, (s: State, fn: (s: State) => State) => fn(s));
  const [saving, startTransition] = React.useTransition();
  const { toasts, push, dismiss } = useToasts();

  const [view, setView] = React.useState<string>("focus"); // "focus" | "all" | area id
  const [filter, setFilter] = React.useState<Filter>(null);
  const [expanded, setExpanded] = React.useState<Set<string>>(() => new Set());
  const [dialog, setDialog] = React.useState<TaskDialogTarget | null>(null);
  const [completing, setCompleting] = React.useState<TaskDTO | null>(null);
  const [uncompleting, setUncompleting] = React.useState<TaskDTO | null>(null);
  const [movingId, setMovingId] = React.useState<string | null>(null);
  const [drag, setDrag] = React.useState<{ activeId: string; cells: Record<string, string[]> } | null>(null);

  const areaById = React.useMemo(() => new Map(data.areas.map((a) => [a.id, a])), [data.areas]);
  const live = React.useMemo(() => data.areas.filter((a) => !a.archived), [data.areas]);
  const focus = React.useMemo(() => (clock ? focusAreas(live, clock) : null), [live, clock]);
  const focusIds = React.useMemo(() => (focus ? new Set(focus.map((a) => a.id)) : null), [focus]);

  // An area view whose area disappeared (archived/deleted elsewhere) falls back to focus.
  const activeView = view === "focus" || view === "all" || live.some((a) => a.id === view) ? view : "focus";

  // Columns: focus areas first; in focus mode the others start collapsed.
  const columns = React.useMemo(() => {
    if (activeView !== "focus" && activeView !== "all") {
      const a = live.find((x) => x.id === activeView);
      return a ? [{ area: a, collapsed: false, focused: !!focusIds?.has(a.id) }] : [];
    }
    const noFocus = !focusIds || focusIds.size === 0;
    const ordered = focusIds ? [...live.filter((a) => focusIds.has(a.id)), ...live.filter((a) => !focusIds.has(a.id))] : live;
    return ordered.map((a) => {
      const focused = !!focusIds?.has(a.id);
      const collapsed = activeView === "focus" && !noFocus && !focused && !expanded.has(a.id);
      return { area: a, collapsed, focused };
    });
  }, [activeView, live, focusIds, expanded]);

  const scopeIds = React.useMemo(
    () => new Set(activeView === "focus" || activeView === "all" ? live.map((a) => a.id) : [activeView]),
    [activeView, live],
  );

  // Undone tasks grouped per cell (all live areas), sorted.
  const cells = React.useMemo(() => {
    const out: Record<string, TaskDTO[]> = {};
    for (const a of live) for (const b of BUCKETS) out[cellKey(a.id, b.id)] = [];
    for (const t of state.open) out[cellKey(t.areaId, t.bucket)]?.push(t);
    for (const k in out) out[k].sort(compareTasks);
    return out;
  }, [live, state.open]);

  const taskById = React.useMemo(() => new Map(state.open.map((t) => [t.id, t])), [state.open]);

  const matches = React.useCallback(
    (t: TaskDTO, f: Filter, c: LocalClock | null) => {
      if (!f || f === "done") return true;
      if (!c) return false;
      if (f === "today") return t.dueDate === c.date;
      if (f === "mepet") return isMepet(t, c.date) && !isOverdue(t, c);
      return isOverdue(t, c);
    },
    [],
  );

  const counts = React.useMemo(() => {
    const inScope = state.open.filter((t) => scopeIds.has(t.areaId));
    return {
      today: inScope.filter((t) => matches(t, "today", clock)).length,
      mepet: inScope.filter((t) => matches(t, "mepet", clock)).length,
      overdue: inScope.filter((t) => matches(t, "overdue", clock)).length,
    };
  }, [state.open, scopeIds, clock, matches]);

  // ---------- Mutations (optimistic; useOptimistic rolls back when the action fails) ----------

  const mutate = React.useCallback(
    <T extends object>(fn: (s: State) => State, action: () => Promise<TaskActionResult<T>>, onOk?: (r: T) => void) => {
      startTransition(async () => {
        addOptimistic(fn);
        let res: TaskActionResult<T>;
        try {
          res = await action();
        } catch {
          res = { ok: false, error: "Something went wrong" };
        }
        if (res.ok) onOk?.(res);
        else push({ text: errorText(res.error), tone: "error" });
      });
    },
    [addOptimistic, push],
  );

  const endOfCell = (cell: Cell) => {
    const list = cells[cellKey(cell.areaId, cell.bucket)] ?? [];
    return list.length ? Math.max(...list.map((t) => t.sortOrder)) + 1 : 0;
  };

  function uncomplete(task: TaskDTO, deleteExpense: boolean) {
    mutate(
      (s) => ({
        done: s.done.filter((t) => t.id !== task.id),
        open: [
          ...s.open.filter((t) => t.id !== task.id),
          { ...task, done: false, doneAt: null, transactionId: deleteExpense ? null : task.transactionId },
        ],
      }),
      () => uncompleteTask(task.id, { deleteExpense }),
      () => push({ text: deleteExpense ? "Tugas dibuka lagi, pengeluaran dihapus" : "Tugas dibuka lagi", tone: "info" }),
    );
  }

  function complete(task: TaskDTO, record: { walletId: string } | null) {
    const next = nextOccurrence(task);
    const now = new Date().toISOString();
    mutate(
      (s) => {
        const open = s.open.filter((t) => t.id !== task.id);
        if (next && !open.some((t) => t.id === next.id) && !s.done.some((t) => t.id === next.id)) {
          open.push({ ...next.data, id: next.id, createdAt: now });
        }
        return { open, done: [{ ...task, done: true, doneAt: now }, ...s.done.filter((t) => t.id !== task.id)] };
      },
      () => completeTask(task.id, { recordExpense: record ? { walletId: record.walletId } : undefined }),
      (r) => {
        const recorded = !!r.transactionId && !task.transactionId;
        const parts = [recorded ? "Selesai, pengeluaran dicatat ✓" : "Tugas selesai ✓"];
        if (next) parts.push(`Berikutnya: ${formatDueDate(next.data.dueDate, clock?.date ?? null)}`);
        push({
          text: parts.join(" · "),
          tone: "success",
          action: { label: "Batalkan", run: () => uncomplete({ ...task, transactionId: r.transactionId }, recorded) },
        });
      },
    );
  }

  function toggle(task: TaskDTO) {
    if (task.done) {
      if (task.transactionId) setUncompleting(task);
      else uncomplete(task, false);
    } else if (task.amount != null && !task.transactionId) {
      setCompleting(task);
    } else {
      complete(task, null);
    }
  }

  const tmpSeq = React.useRef(0);
  function quickAdd(cell: Cell, title: string) {
    const now = new Date().toISOString();
    const temp: TaskDTO = {
      id: `tmp-${++tmpSeq.current}`,
      areaId: cell.areaId,
      title,
      note: null,
      bucket: cell.bucket,
      dueDate: null,
      dueTime: null,
      remindBefore: null,
      recurrence: null,
      seriesId: null,
      done: false,
      doneAt: null,
      sortOrder: endOfCell(cell),
      amount: null,
      walletId: null,
      categoryId: null,
      transactionId: null,
      createdAt: now,
    };
    mutate((s) => ({ ...s, open: [...s.open, temp] }), () => createTask({ areaId: cell.areaId, bucket: cell.bucket, title }));
  }

  function reorder(cell: Cell, ids: string[]) {
    mutate(
      (s) => ({
        ...s,
        open: s.open.map((t) => {
          const i = ids.indexOf(t.id);
          return i < 0 ? t : { ...t, areaId: cell.areaId, bucket: cell.bucket, sortOrder: i };
        }),
      }),
      () => reorderTasks(cell, ids),
    );
  }

  function moveTo(task: TaskDTO, to: Cell) {
    const sortOrder = endOfCell(to);
    setMovingId(null);
    mutate(
      (s) => ({ ...s, open: s.open.map((t) => (t.id === task.id ? { ...t, ...to, sortOrder } : t)) }),
      () => moveTask(task.id, { ...to, sortOrder }),
      () => {
        const b = BUCKETS.find((x) => x.id === to.bucket)!;
        push({ text: `Dipindah ke ${b.emoji} ${b.label} · ${areaById.get(to.areaId)?.name ?? ""}`, tone: "info" });
      },
    );
  }

  function nudge(task: TaskDTO, dir: -1 | 1) {
    const ids = (cells[cellKey(task.areaId, task.bucket)] ?? []).map((t) => t.id);
    const i = ids.indexOf(task.id);
    const j = i + dir;
    if (i < 0 || j < 0 || j >= ids.length) return;
    reorder({ areaId: task.areaId, bucket: task.bucket }, arrayMove(ids, i, j));
  }

  function removeTask(task: TaskDTO, run: () => Promise<{ ok: boolean; error?: string }>) {
    mutate(
      (s) => ({ open: s.open.filter((t) => t.id !== task.id), done: s.done.filter((t) => t.id !== task.id) }),
      async () => {
        const r = await run();
        return r.ok ? { ok: true as const } : { ok: false as const, error: r.error ?? "Something went wrong" };
      },
      () => push({ text: "Tugas dihapus", tone: "info" }),
    );
  }

  // ---------- Drag & drop ----------

  const sensors = useSensors(
    useSensor(MousePointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 220, tolerance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  const dndEnabled = !filter;

  const containerOf = (id: UniqueIdentifier, cellsNow: Record<string, string[]>) => {
    const s = String(id);
    if (s.startsWith(DROP_PREFIX)) return s.slice(DROP_PREFIX.length);
    return Object.keys(cellsNow).find((k) => cellsNow[k].includes(s)) ?? null;
  };

  function onDragStart(e: DragStartEvent) {
    setDrag({
      activeId: String(e.active.id),
      cells: Object.fromEntries(Object.entries(cells).map(([k, list]) => [k, list.map((t) => t.id)])),
    });
  }

  function onDragOver({ active, over }: DragOverEvent) {
    if (!over || !drag) return;
    const from = containerOf(active.id, drag.cells);
    const to = containerOf(over.id, drag.cells);
    if (!from || !to || from === to || !(to in drag.cells)) return;
    setDrag((d) => {
      if (!d) return d;
      const id = String(active.id);
      const fromItems = d.cells[from].filter((x) => x !== id);
      const toItems = d.cells[to].filter((x) => x !== id);
      let idx = isCellId(over.id) ? toItems.length : toItems.indexOf(String(over.id));
      if (idx < 0) idx = toItems.length;
      else if (!isCellId(over.id)) {
        const r = active.rect.current.translated;
        if (r && r.top > over.rect.top + over.rect.height / 2) idx += 1;
      }
      toItems.splice(idx, 0, id);
      return { ...d, cells: { ...d.cells, [from]: fromItems, [to]: toItems } };
    });
  }

  function onDragEnd({ active, over }: DragEndEvent) {
    const d = drag;
    setDrag(null);
    if (!d || !over) return;
    const id = String(active.id);
    const cont = containerOf(id, d.cells);
    if (!cont) return;
    let ids = d.cells[cont];
    const overCont = containerOf(over.id, d.cells);
    if (overCont === cont && !isCellId(over.id) && over.id !== active.id) {
      ids = arrayMove(ids, ids.indexOf(id), ids.indexOf(String(over.id)));
    }
    const task = taskById.get(id);
    if (!task) return;
    const origKey = cellKey(task.areaId, task.bucket);
    const orig = (cells[origKey] ?? []).map((t) => t.id);
    if (cont === origKey && ids.length === orig.length && ids.every((x, i) => x === orig[i])) return;
    reorder(parseCell(cont), ids);
  }

  const itemsFor = (key: string): TaskDTO[] => {
    if (drag) return (drag.cells[key] ?? []).map((id) => taskById.get(id)).filter((t): t is TaskDTO => !!t);
    return cells[key] ?? [];
  };

  const activeTask = drag ? taskById.get(drag.activeId) : undefined;
  const movingTask = movingId ? (taskById.get(movingId) ?? null) : null;
  const movingPos = movingTask
    ? (() => {
        const list = cells[cellKey(movingTask.areaId, movingTask.bucket)] ?? [];
        return { index: list.findIndex((t) => t.id === movingTask.id), size: list.length };
      })()
    : null;

  // ---------- Render ----------

  const firstArea = columns.find((c) => !c.collapsed)?.area ?? live[0];

  return (
    <div className="min-w-0">
      <PageHeader
        title="Tugas"
        description="🔥 FIRE hari ini/besok · ✨ WANT 1–2 minggu · 📋 SHOULD kapan saja"
        action={
          <div className="flex items-center gap-2">
            <SavingHint pending={saving} />
            <Link href="/tasks/areas">
              <Button variant="outline">
                <LinkPendingIcon>
                  <Settings2 className="h-4 w-4" />
                </LinkPendingIcon>{" "}
                Kelola area
              </Button>
            </Link>
            {firstArea && (
              <Button onClick={() => setDialog({ mode: "create", areaId: firstArea.id, bucket: "fire" })}>
                <Plus className="h-4 w-4" /> Tugas baru
              </Button>
            )}
          </div>
        }
      />

      {live.length === 0 ? (
        <EmptyState
          icon={ListTodo}
          title="Semua area diarsipkan"
          description="Aktifkan lagi atau buat area baru untuk mulai menambah tugas."
          action={
            <Link href="/tasks/areas">
              <Button>
                <LinkPendingIcon /> Kelola area
              </Button>
            </Link>
          }
        />
      ) : (
        <>
          {/* Area switcher */}
          <div className="-mx-4 mb-3 overflow-x-auto px-4 sm:mx-0 sm:px-0">
            <div className="flex w-max gap-1.5" role="tablist" aria-label="Pilih area">
              <ViewTab active={activeView === "focus"} onClick={() => setView("focus")}>
                🎯 Fokus
              </ViewTab>
              {live.map((a) => (
                <ViewTab key={a.id} active={activeView === a.id} onClick={() => setView(a.id)}>
                  <span className="h-2 w-2 rounded-full" style={{ background: a.color }} />
                  {a.name}
                </ViewTab>
              ))}
              <ViewTab active={activeView === "all"} onClick={() => setView("all")}>
                Semua
              </ViewTab>
            </div>
          </div>

          {activeView === "focus" && (
            <p className="mb-3 text-xs text-muted">
              {!focus
                ? "Menyesuaikan dengan jam perangkatmu…"
                : focus.length === 0
                  ? "Tidak ada area yang aktif sekarang — semua area ditampilkan."
                  : focus.some((a) => a.schedule)
                    ? `Fokus sekarang (${clock?.time}): ${focus.map((a) => a.name).join(", ")} — sesuai jadwal area.`
                    : `Di luar jadwal (${clock?.time}) — fokus ke ${focus.map((a) => a.name).join(", ")}.`}
            </p>
          )}

          {/* Filters */}
          <div className="-mx-4 mb-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
            <div className="flex w-max gap-1.5" aria-label="Filter">
              <FilterChip active={filter === null} onClick={() => setFilter(null)}>
                Semua tugas
              </FilterChip>
              <FilterChip active={filter === "today"} onClick={() => setFilter(filter === "today" ? null : "today")} count={counts.today}>
                Hari ini
              </FilterChip>
              <FilterChip
                active={filter === "mepet"}
                onClick={() => setFilter(filter === "mepet" ? null : "mepet")}
                count={counts.mepet}
                tone="#FF4B4B"
              >
                🔥 Mepet
              </FilterChip>
              <FilterChip
                active={filter === "overdue"}
                onClick={() => setFilter(filter === "overdue" ? null : "overdue")}
                count={counts.overdue}
                tone="#FF4B4B"
              >
                Terlambat
              </FilterChip>
              <FilterChip active={filter === "done"} onClick={() => setFilter(filter === "done" ? null : "done")}>
                <CheckCircle2 className="h-3.5 w-3.5" /> Selesai
              </FilterChip>
            </div>
          </div>

          {filter === "done" ? (
            <DoneList
              tasks={state.done.filter((t) => scopeIds.has(t.areaId))}
              areaById={areaById}
              clock={clock}
              currency={data.currency}
              onToggle={toggle}
              onOpen={(t) => setDialog({ mode: "edit", task: t })}
            />
          ) : (
            <>
              {filter && (
                <p className="mb-3 text-xs text-muted">
                  Filter aktif — seret & lepas dimatikan. Pakai tombol “Pindah ke…” pada kartu.
                </p>
              )}
              <DndContext
                id="task-board-dnd"
                sensors={sensors}
                collisionDetection={collision}
                onDragStart={onDragStart}
                onDragOver={onDragOver}
                onDragEnd={onDragEnd}
                onDragCancel={() => setDrag(null)}
                accessibility={{
                  screenReaderInstructions: {
                    draggable:
                      "Tekan spasi atau Enter untuk mengangkat tugas, panah untuk memindah, spasi/Enter lagi untuk melepas, Escape untuk batal.",
                  },
                }}
              >
                <div className="-mx-4 overflow-x-auto px-4 pb-3 sm:mx-0 sm:px-0">
                  <div
                    className="grid w-max gap-3"
                    style={{
                      gridTemplateColumns: columns.map((c) => (c.collapsed ? "48px" : "minmax(264px, 300px)")).join(" "),
                    }}
                  >
                    {columns.map((c, ci) =>
                      c.collapsed ? (
                        <CollapsedColumn
                          key={c.area.id}
                          area={c.area}
                          col={ci + 1}
                          count={BUCKETS.reduce((n, b) => n + (cells[cellKey(c.area.id, b.id)]?.length ?? 0), 0)}
                          onExpand={() => setExpanded((s) => new Set(s).add(c.area.id))}
                        />
                      ) : (
                        <React.Fragment key={c.area.id}>
                          <AreaHeader
                            area={c.area}
                            col={ci + 1}
                            focused={c.focused && activeView !== c.area.id}
                            count={BUCKETS.reduce((n, b) => n + (cells[cellKey(c.area.id, b.id)]?.length ?? 0), 0)}
                            onCollapse={
                              activeView === "focus" && expanded.has(c.area.id) && !c.focused
                                ? () =>
                                    setExpanded((s) => {
                                      const n = new Set(s);
                                      n.delete(c.area.id);
                                      return n;
                                    })
                                : undefined
                            }
                            onAdd={() => setDialog({ mode: "create", areaId: c.area.id, bucket: "fire" })}
                          />
                          {BUCKETS.map((b, bi) => {
                            const key = cellKey(c.area.id, b.id);
                            const items = itemsFor(key).filter((t) => matches(t, filter, clock));
                            return (
                              <BucketCell
                                key={key}
                                cellId={key}
                                bucket={b}
                                col={ci + 1}
                                row={bi + 2}
                                items={items}
                                clock={clock}
                                currency={data.currency}
                                dndEnabled={dndEnabled}
                                filtered={!!filter}
                                onToggle={toggle}
                                onOpen={(t) => setDialog({ mode: "edit", task: t })}
                                onMove={(t) => setMovingId(t.id)}
                                onQuickAdd={(title) => quickAdd({ areaId: c.area.id, bucket: b.id }, title)}
                              />
                            );
                          })}
                        </React.Fragment>
                      ),
                    )}
                  </div>
                </div>
                <DragOverlay dropAnimation={null}>
                  {activeTask ? (
                    <TaskCardBody task={activeTask} clock={clock} currency={data.currency} overlay className="w-[264px]" />
                  ) : null}
                </DragOverlay>
              </DndContext>
            </>
          )}
        </>
      )}

      <TaskDialog
        target={dialog}
        onClose={() => setDialog(null)}
        onDeleted={removeTask}
        areas={data.areas}
        wallets={data.wallets}
        categories={data.categories}
        currency={data.currency}
      />
      <CompleteExpenseDialog
        task={completing}
        wallets={data.wallets}
        currency={data.currency}
        onClose={() => setCompleting(null)}
        onConfirm={(t, record) => {
          setCompleting(null);
          complete(t, record);
        }}
      />
      <UncompleteDialog
        task={uncompleting}
        currency={data.currency}
        onClose={() => setUncompleting(null)}
        onConfirm={(t, del) => {
          setUncompleting(null);
          uncomplete(t, del);
        }}
      />
      <MoveDialog
        task={movingTask}
        areas={data.areas}
        position={movingPos}
        onClose={() => setMovingId(null)}
        onMove={moveTo}
        onNudge={nudge}
      />
      <Toasts toasts={toasts} dismiss={dismiss} />
    </div>
  );
}

// ---------- Pieces ----------

function ViewTab({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={cn(
        "inline-flex h-9 items-center gap-1.5 whitespace-nowrap rounded-full border px-3.5 text-sm font-medium transition",
        active ? "border-primary bg-primary text-white" : "border-border bg-surface text-muted hover:bg-accent hover:text-foreground",
      )}
    >
      {children}
    </button>
  );
}

function FilterChip({
  active,
  onClick,
  count,
  tone,
  children,
}: {
  active: boolean;
  onClick: () => void;
  count?: number;
  tone?: string;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      aria-pressed={active}
      onClick={onClick}
      className={cn(
        "inline-flex h-8 items-center gap-1.5 whitespace-nowrap rounded-lg px-3 text-xs font-semibold transition",
        active ? "bg-foreground text-surface" : "bg-accent text-muted hover:text-foreground",
      )}
    >
      {children}
      {count != null && count > 0 && (
        <span
          className="rounded-full px-1.5 text-[11px] leading-4 text-white"
          style={{ background: active ? "rgba(255,255,255,.25)" : (tone ?? "var(--color-muted-soft)") }}
        >
          {count}
        </span>
      )}
    </button>
  );
}

function AreaIcon({ area, size = "md" }: { area: AreaDTO; size?: "sm" | "md" }) {
  return (
    <span
      className={cn("flex shrink-0 items-center justify-center rounded-full", size === "md" ? "h-8 w-8" : "h-7 w-7")}
      style={{ background: `${area.color}1f`, color: area.color }}
    >
      <CategoryIcon name={area.icon} className="h-4 w-4" />
    </span>
  );
}

function AreaHeader({
  area,
  col,
  focused,
  count,
  onCollapse,
  onAdd,
}: {
  area: AreaDTO;
  col: number;
  focused: boolean;
  count: number;
  onCollapse?: () => void;
  onAdd: () => void;
}) {
  return (
    <div
      className="flex min-w-0 items-center gap-2 rounded-xl border border-border bg-card px-3 py-2 shadow-sm"
      style={{ gridColumn: col, gridRow: 1, borderTopColor: area.color, borderTopWidth: 3 }}
    >
      <AreaIcon area={area} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="truncate text-sm font-semibold text-foreground">{area.name}</span>
          <span className="rounded px-1 text-[10px] font-bold tracking-wide" style={{ background: `${area.color}1f`, color: area.color }}>
            {area.code}
          </span>
          {focused && <span className="rounded bg-primary-soft px-1 text-[10px] font-semibold text-primary">FOKUS</span>}
        </div>
        <p className="truncate text-[11px] text-muted">
          {scheduleLabel(area.schedule)} · {count} tugas
        </p>
      </div>
      <button type="button" onClick={onAdd} aria-label={`Tambah tugas di ${area.name}`} className="rounded-md p-1 text-muted hover:bg-accent hover:text-foreground">
        <Plus className="h-4 w-4" />
      </button>
      {onCollapse && (
        <button type="button" onClick={onCollapse} aria-label={`Ciutkan ${area.name}`} className="rounded-md p-1 text-muted hover:bg-accent hover:text-foreground">
          <ChevronLeft className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}

function CollapsedColumn({ area, col, count, onExpand }: { area: AreaDTO; col: number; count: number; onExpand: () => void }) {
  return (
    <button
      type="button"
      onClick={onExpand}
      aria-label={`Buka ${area.name} (${count} tugas)`}
      title={`Buka ${area.name}`}
      className="flex flex-col items-center gap-2 rounded-xl border border-dashed border-border bg-surface py-3 text-muted transition hover:bg-accent hover:text-foreground"
      style={{ gridColumn: col, gridRow: "1 / span 4" }}
    >
      <ChevronRight className="h-4 w-4" />
      <AreaIcon area={area} size="sm" />
      <span className="text-xs font-semibold [writing-mode:vertical-rl]">{area.name}</span>
      <span className="rounded-full bg-accent px-1.5 text-[11px] font-semibold">{count}</span>
    </button>
  );
}

function BucketCell({
  cellId,
  bucket,
  col,
  row,
  items,
  clock,
  currency,
  dndEnabled,
  filtered,
  onToggle,
  onOpen,
  onMove,
  onQuickAdd,
}: {
  cellId: string;
  bucket: (typeof BUCKETS)[number];
  col: number;
  row: number;
  items: TaskDTO[];
  clock: LocalClock | null;
  currency: string;
  dndEnabled: boolean;
  filtered: boolean;
  onToggle: (t: TaskDTO) => void;
  onOpen: (t: TaskDTO) => void;
  onMove: (t: TaskDTO) => void;
  onQuickAdd: (title: string) => void;
}) {
  const { setNodeRef, isOver } = useDroppable({ id: DROP_PREFIX + cellId, disabled: !dndEnabled });
  const [title, setTitle] = React.useState("");

  return (
    <section
      ref={setNodeRef}
      aria-label={`${bucket.label}`}
      className={cn("flex min-w-0 flex-col rounded-xl border p-2 transition", isOver ? "ring-2" : "")}
      style={{
        gridColumn: col,
        gridRow: row,
        background: `${bucket.color}0d`,
        borderColor: `${bucket.color}40`,
        ...(isOver ? { ["--tw-ring-color" as string]: `${bucket.color}80` } : {}),
      }}
    >
      <header className="mb-2 flex items-center gap-1.5 px-1">
        <span className="text-xs font-bold tracking-wide" style={{ color: bucket.color }}>
          {bucket.emoji} {bucket.label}
        </span>
        <span className="truncate text-[11px] text-muted">{bucket.meaning}</span>
        <span className="ml-auto text-[11px] font-semibold text-muted">{items.length || ""}</span>
      </header>

      <SortableContext items={items.map((t) => t.id)} strategy={verticalListSortingStrategy} disabled={!dndEnabled}>
        <div className="flex min-h-10 flex-1 flex-col gap-2">
          {items.map((t) => (
            <SortableTaskCard
              key={t.id}
              task={t}
              clock={clock}
              currency={currency}
              dragDisabled={!dndEnabled}
              onCheck={onToggle}
              onOpen={onOpen}
              onMove={onMove}
            />
          ))}
          {items.length === 0 && (
            <p className="rounded-lg border border-dashed px-2 py-2.5 text-center text-[11px] text-muted-soft" style={{ borderColor: `${bucket.color}40` }}>
              {filtered ? "Tidak ada" : "Kosong — seret tugas ke sini"}
            </p>
          )}
        </div>
      </SortableContext>

      {!filtered && (
        <form
          className="mt-2"
          onSubmit={(e) => {
            e.preventDefault();
            const v = title.trim();
            if (!v) return;
            onQuickAdd(v);
            setTitle("");
          }}
        >
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={200}
            placeholder={`+ Tambah ${bucket.label}…`}
            aria-label={`Tambah tugas ${bucket.label}`}
            className="h-8 w-full rounded-lg border border-transparent bg-transparent px-2 text-sm text-foreground placeholder:text-muted-soft outline-none transition hover:bg-surface focus:border-border focus:bg-surface"
          />
        </form>
      )}
    </section>
  );
}

function DoneList({
  tasks,
  areaById,
  clock,
  currency,
  onToggle,
  onOpen,
}: {
  tasks: TaskDTO[];
  areaById: Map<string, AreaDTO>;
  clock: LocalClock | null;
  currency: string;
  onToggle: (t: TaskDTO) => void;
  onOpen: (t: TaskDTO) => void;
}) {
  const sorted = [...tasks].sort((a, b) => (b.doneAt ?? "").localeCompare(a.doneAt ?? ""));
  if (sorted.length === 0) {
    return <EmptyState icon={CheckCircle2} title="Belum ada tugas selesai" description="Tugas yang kamu centang muncul di sini." />;
  }
  return (
    <div className="space-y-2">
      {sorted.map((t) => (
        <div key={t.id} className="flex flex-wrap items-center gap-x-3 gap-y-1">
          <TaskCardBody
            task={t}
            clock={clock}
            currency={currency}
            area={areaById.get(t.areaId)}
            onCheck={onToggle}
            onOpen={onOpen}
            className="min-w-0 flex-1"
          />
          {t.doneAt && <span className="w-full text-right text-[11px] text-muted sm:w-40">Selesai {formatDoneAt(t.doneAt)}</span>}
        </div>
      ))}
      <p className="pt-2 text-center text-xs text-muted">Menampilkan hingga 200 tugas terakhir yang selesai.</p>
    </div>
  );
}
