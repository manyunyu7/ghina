"use client";

import * as React from "react";
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  TouchSensor,
  pointerWithin,
  rectIntersection,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  type CollisionDetection,
  type DragEndEvent,
} from "@dnd-kit/core";
import { BadgeDollarSign, CalendarClock, CheckSquare, ChevronsRight, Clapperboard, Filter, GripVertical, Plus, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/input";
import {
  FORMATS,
  needsMetricsPrompt,
  platformLabel,
  STAGES,
  stageInfo,
  type StageId,
} from "@/lib/content";
import { cn, formatCurrency } from "@/lib/utils";
import { createContentItem, moveContentStage } from "./actions";
import { usePlanner } from "./planner";
import { AccountAvatar, formatDateTime, handleText, PillarChip, pillarColor, useNow, useToast } from "./ui";
import type { ContentItemDTO, ContentPostDTO } from "./types";

/** Mouse/pen only — touch goes through the long-press TouchSensor so swiping still scrolls. */
class MousePointerSensor extends PointerSensor {
  static activators = [
    {
      eventName: "onPointerDown" as const,
      handler: ({ nativeEvent: e }: React.PointerEvent) => e.isPrimary && e.button === 0 && e.pointerType !== "touch",
    },
  ];
}

const pointerCollision: CollisionDetection = (args) => {
  const hits = pointerWithin(args);
  return hits.length ? hits : rectIntersection(args);
};

const COLUMN_PREFIX = "stage:";

export function Board() {
  const { data, state, mutate, openItem } = usePlanner();
  const toast = useToast();
  const [account, setAccount] = React.useState("");
  const [pillar, setPillar] = React.useState("");
  const [format, setFormat] = React.useState("");
  const [activeId, setActiveId] = React.useState<string | null>(null);
  const [showFilters, setShowFilters] = React.useState(false);

  const postsByItem = React.useMemo(() => {
    const m = new Map<string, ContentPostDTO[]>();
    for (const p of state.posts) m.set(p.contentId, [...(m.get(p.contentId) ?? []), p]);
    return m;
  }, [state.posts]);

  const filtered = state.items.filter((i) => {
    if (format && (format === "-" ? i.format : i.format !== format)) return false;
    if (pillar && (pillar === "-" ? i.pillar : (i.pillar ?? "").toLocaleLowerCase("id-ID") !== pillar.toLocaleLowerCase("id-ID"))) return false;
    if (account && !(postsByItem.get(i.id) ?? []).some((p) => p.accountId === account)) return false;
    return true;
  });
  const filtering = !!(account || pillar || format);

  function move(item: ContentItemDTO, stage: StageId) {
    if (item.stage === stage) return;
    mutate(
      (s) => ({ ...s, items: s.items.map((i) => (i.id === item.id ? { ...i, stage } : i)) }),
      () => moveContentStage(item.id, stage),
      () => toast({ text: `Dipindah ke ${stageInfo(stage).label}`, tone: "info" }),
    );
  }

  const tmp = React.useRef(0);
  function quickAdd(title: string) {
    const now = new Date().toISOString();
    const temp: ContentItemDTO = {
      id: `tmp-${++tmp.current}`,
      createdAt: now,
      updatedAt: now,
      title,
      stage: "ide",
      format: format && format !== "-" ? format : null,
      pillar: pillar && pillar !== "-" ? pillar : null,
      idea: "",
      noteId: null,
      checklist: [],
      photos: [],
      assetLinks: [],
      sponsor: null,
    };
    mutate(
      (s) => ({ ...s, items: [temp, ...s.items] }),
      () => createContentItem({ title, stage: "ide", format: temp.format as never, pillar: temp.pillar }),
    );
  }

  const sensors = useSensors(
    useSensor(MousePointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 220, tolerance: 8 } }),
  );

  function onDragEnd(e: DragEndEvent) {
    setActiveId(null);
    const over = e.over ? String(e.over.id) : null;
    if (!over?.startsWith(COLUMN_PREFIX)) return;
    const item = state.items.find((i) => i.id === String(e.active.id));
    if (item) move(item, over.slice(COLUMN_PREFIX.length) as StageId);
  }

  const active = activeId ? state.items.find((i) => i.id === activeId) : null;
  const liveAccounts = data.accounts.filter((a) => !a.archived);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Button variant="outline" size="sm" className="sm:hidden" onClick={() => setShowFilters((v) => !v)} aria-expanded={showFilters}>
          <Filter className="h-4 w-4" /> Filter{filtering ? " (aktif)" : ""}
        </Button>
        <div className={cn("w-full flex-wrap items-center gap-2 sm:flex sm:w-auto", showFilters ? "flex" : "hidden")}>
          <Select aria-label="Filter akun" value={account} onChange={(e) => setAccount(e.target.value)} className="h-9 w-full sm:w-48">
            <option value="">Semua akun</option>
            {liveAccounts.map((a) => (
              <option key={a.id} value={a.id}>
                {platformLabel(a)} {handleText(a.handle)}
              </option>
            ))}
          </Select>
          <Select aria-label="Filter pilar" value={pillar} onChange={(e) => setPillar(e.target.value)} className="h-9 w-full sm:w-44">
            <option value="">Semua pilar</option>
            {data.pillars.map((p) => (
              <option key={p.id} value={p.name}>
                {p.name}
              </option>
            ))}
            <option value="-">Tanpa pilar</option>
          </Select>
          <Select aria-label="Filter format" value={format} onChange={(e) => setFormat(e.target.value)} className="h-9 w-full sm:w-40">
            <option value="">Semua format</option>
            {FORMATS.map((f) => (
              <option key={f.id} value={f.id}>
                {f.label}
              </option>
            ))}
            <option value="-">Tanpa format</option>
          </Select>
          {filtering && (
            <Button variant="ghost" size="sm" onClick={() => (setAccount(""), setPillar(""), setFormat(""))}>
              <X className="h-4 w-4" /> Reset
            </Button>
          )}
        </div>
        <p className="ml-auto hidden text-xs text-muted-soft lg:block">Seret kartu ke kolom lain untuk pindah tahap.</p>
      </div>

      {state.items.length === 0 && (
        <p className="mb-3 rounded-lg bg-accent px-3 py-2 text-sm text-muted">
          <Clapperboard className="mr-1 inline h-4 w-4 align-[-3px]" /> Belum ada konten. Tulis ide pertamamu di kolom <b>Ide</b>, atau
          ambil dari tab <b>Ide masuk</b>.
        </p>
      )}

      <DndContext
        id="content-board"
        sensors={sensors}
        collisionDetection={pointerCollision}
        onDragStart={(e) => setActiveId(String(e.active.id))}
        onDragCancel={() => setActiveId(null)}
        onDragEnd={onDragEnd}
      >
        <div className="-mx-4 overflow-x-auto px-4 pb-4 sm:mx-0 sm:px-0">
          <div className="flex min-w-max gap-3">
            {STAGES.map((s) => {
              const list = filtered.filter((i) => i.stage === s.id);
              return (
                <Column key={s.id} stage={s.id} label={s.label} color={s.color} count={list.length}>
                  {s.id === "ide" && <QuickAdd onAdd={quickAdd} />}
                  {list.map((item) => (
                    <DraggableCard key={item.id} item={item} posts={postsByItem.get(item.id) ?? []} onOpen={() => openItem({ mode: "edit", id: item.id })} onMove={(st) => move(item, st)} dimmed={activeId === item.id} />
                  ))}
                  {list.length === 0 && s.id !== "ide" && (
                    <p className="rounded-lg border border-dashed border-border px-3 py-6 text-center text-xs text-muted-soft">
                      {filtering ? "Tidak ada yang cocok" : "Seret kartu ke sini"}
                    </p>
                  )}
                </Column>
              );
            })}
          </div>
        </div>
        <DragOverlay dropAnimation={null}>
          {active ? <CardBody item={active} posts={postsByItem.get(active.id) ?? []} overlay /> : null}
        </DragOverlay>
      </DndContext>
    </div>
  );
}

function Column({ stage, label, color, count, children }: { stage: StageId; label: string; color: string; count: number; children: React.ReactNode }) {
  const { setNodeRef, isOver } = useDroppable({ id: COLUMN_PREFIX + stage });
  return (
    <section
      ref={setNodeRef}
      aria-label={`Kolom ${label}`}
      data-stage={stage}
      className={cn(
        "flex w-[272px] shrink-0 flex-col rounded-card border bg-surface/60 p-2 transition",
        isOver ? "border-primary bg-primary-soft/50" : "border-border",
      )}
    >
      <header className="mb-2 flex items-center gap-2 px-1 pt-1">
        <span className="h-2.5 w-2.5 rounded-full" style={{ background: color }} />
        <h2 className="text-sm font-semibold text-foreground">{label}</h2>
        <span className="rounded-full bg-accent px-1.5 text-xs font-medium text-muted">{count}</span>
      </header>
      <div className="flex min-h-24 flex-1 flex-col gap-2">{children}</div>
    </section>
  );
}

function QuickAdd({ onAdd }: { onAdd: (title: string) => void }) {
  const [v, setV] = React.useState("");
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        const t = v.trim();
        if (!t) return;
        onAdd(t);
        setV("");
      }}
      className="flex gap-1"
    >
      <input
        value={v}
        onChange={(e) => setV(e.target.value)}
        maxLength={200}
        placeholder="+ Tulis ide cepat…"
        aria-label="Tambah ide cepat"
        className="h-9 min-w-0 flex-1 rounded-lg border border-dashed border-border bg-card px-2.5 text-sm outline-none placeholder:text-muted-soft focus:border-primary focus:ring-2 focus:ring-primary/20"
      />
      {v.trim() && (
        <Button type="submit" size="icon" className="h-9 w-9" aria-label="Simpan ide">
          <Plus className="h-4 w-4" />
        </Button>
      )}
    </form>
  );
}

function DraggableCard({
  item,
  posts,
  onOpen,
  onMove,
  dimmed,
}: {
  item: ContentItemDTO;
  posts: ContentPostDTO[];
  onOpen: () => void;
  onMove: (s: StageId) => void;
  dimmed: boolean;
}) {
  const temp = item.id.startsWith("tmp-");
  // Pointer/touch drag only; keyboard users move cards with the "Pindah tahap" menu.
  const { listeners, setNodeRef, setActivatorNodeRef } = useDraggable({ id: item.id, disabled: temp });
  return (
    <div ref={setNodeRef} className={cn(dimmed && "opacity-40", temp && "opacity-60")}>
      {/* A temp (optimistic, unsaved) card has no server id yet: no open / move. */}
      <CardBody item={item} posts={posts} onOpen={temp ? undefined : onOpen} onMove={temp ? undefined : onMove} handle={listeners} activatorRef={setActivatorNodeRef} />
    </div>
  );
}

function CardBody({
  item,
  posts,
  onOpen,
  onMove,
  handle,
  activatorRef,
  overlay,
}: {
  item: ContentItemDTO;
  posts: ContentPostDTO[];
  onOpen?: () => void;
  onMove?: (s: StageId) => void;
  handle?: React.HTMLAttributes<HTMLElement>;
  activatorRef?: (el: HTMLElement | null) => void;
  overlay?: boolean;
}) {
  const { data, accountById, tz } = usePlanner();
  const [menu, setMenu] = React.useState(false);
  const now = useNow();
  const next = posts
    .filter((p) => p.status === "scheduled" && p.scheduledAt && new Date(p.scheduledAt).getTime() >= now - 3600_000)
    .map((p) => p.scheduledAt!)
    .sort()[0];
  const done = item.checklist.filter((c) => c.done).length;
  const metricsDue = now > 0 && posts.some((p) => needsMetricsPrompt(p, new Date(now)));
  const fmt = FORMATS.find((f) => f.id === item.format);

  return (
    <article
      {...handle}
      ref={activatorRef}
      aria-roledescription="kartu konten"
      aria-label={item.title}
      onClick={(e) => {
        if ((e.target as HTMLElement).closest("button,a")) return;
        onOpen?.();
      }}
      className={cn(
        "group relative cursor-grab touch-manipulation rounded-xl border border-border bg-card p-3 text-left shadow-sm outline-none transition hover:border-primary/40 focus-visible:ring-2 focus-visible:ring-primary/40 active:cursor-grabbing",
        overlay && "rotate-1 shadow-xl",
      )}
    >
      <div className="flex items-start gap-1.5">
        <GripVertical className="mt-0.5 h-4 w-4 shrink-0 text-muted-soft" aria-hidden />
        <button type="button" onClick={onOpen} className="min-w-0 flex-1 text-left text-sm font-semibold text-foreground hover:text-primary">
          <span className="line-clamp-3 break-words">{item.title}</span>
        </button>
        {onMove && (
          <button
            type="button"
            onClick={() => setMenu((v) => !v)}
            aria-label={`Pindah tahap: ${item.title}`}
            aria-expanded={menu}
            className="-mr-1 -mt-1 rounded-md p-1 text-muted-soft transition hover:bg-accent hover:text-foreground"
          >
            <ChevronsRight className="h-4 w-4" />
          </button>
        )}
      </div>
      {menu && onMove && (
        <div role="menu" className="mt-2 grid grid-cols-2 gap-1 rounded-lg border border-border bg-surface p-1">
          {STAGES.map((s) => (
            <button
              key={s.id}
              role="menuitem"
              type="button"
              disabled={s.id === item.stage}
              onClick={() => {
                setMenu(false);
                onMove(s.id);
              }}
              className="flex items-center gap-1.5 rounded-md px-2 py-1 text-left text-xs font-medium text-foreground hover:bg-accent disabled:opacity-40"
            >
              <span className="h-2 w-2 rounded-full" style={{ background: s.color }} />
              {s.label}
            </button>
          ))}
        </div>
      )}

      {(fmt || item.pillar) && (
        <div className="mt-2 flex flex-wrap items-center gap-1">
          {fmt && <span className="rounded-full bg-accent px-2 py-0.5 text-[11px] font-medium text-muted">{fmt.label}</span>}
          {item.pillar && <PillarChip name={item.pillar} color={pillarColor(data.pillars, item.pillar)} />}
        </div>
      )}

      {(posts.length > 0 || item.sponsor || item.checklist.length > 0 || next || metricsDue) && (
        <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1.5">
          {posts.length > 0 && (
            <div className="flex -space-x-1.5">
              {posts.map((p) => {
                const a = accountById.get(p.accountId);
                return a ? <AccountAvatar key={p.id} account={a} status={p.status} size="sm" /> : null;
              })}
            </div>
          )}
          {item.checklist.length > 0 && (
            <span className={cn("inline-flex items-center gap-0.5 text-[11px] font-medium", done === item.checklist.length ? "text-income" : "text-muted")}>
              <CheckSquare className="h-3 w-3" /> {done}/{item.checklist.length}
            </span>
          )}
          {item.sponsor && (
            <span
              className={cn(
                "inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 text-[11px] font-semibold",
                item.sponsor.paid ? "bg-income-soft text-income" : "bg-amber-100 text-amber-800",
              )}
              title={`Sponsor ${item.sponsor.brand}${item.sponsor.amount ? ` · ${formatCurrency(item.sponsor.amount, item.sponsor.currency)}` : " · barter"}`}
            >
              <BadgeDollarSign className="h-3 w-3" />
              {item.sponsor.paid ? "Lunas" : "Belum dibayar"}
            </span>
          )}
          {metricsDue && <span className="rounded-full bg-primary-soft px-1.5 py-0.5 text-[11px] font-semibold text-primary">Isi performa?</span>}
          {next && (
            <span className="inline-flex w-full items-center gap-1 text-[11px] text-muted">
              <CalendarClock className="h-3 w-3" /> {formatDateTime(next, tz)}
            </span>
          )}
        </div>
      )}
    </article>
  );
}
