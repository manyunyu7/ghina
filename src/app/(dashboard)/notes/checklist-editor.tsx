"use client";

import * as React from "react";
import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
  type Modifier,
} from "@dnd-kit/core";
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ChevronDown, ChevronRight, GripVertical, Plus, Trash2, X } from "lucide-react";
import { CHECKLIST_MAX, CHECKLIST_TEXT_MAX, type ChecklistItem } from "@/lib/notes";
import { cn } from "@/lib/utils";
import { newItemId } from "./shared";

/** Drag only up/down. */
const restrictToVerticalAxisModifier: Modifier = ({ transform }) => ({ ...transform, x: 0 });

/**
 * Checklist under the body: add (Enter adds the next row), toggle, edit inline, reorder
 * (drag handle or keyboard: focus the handle, Space, arrows), remove, clear ticked.
 * Unticked items first; ticked ones collapse into "N selesai".
 */
export function ChecklistEditor({
  items,
  onChange,
}: {
  items: ChecklistItem[];
  onChange: (next: ChecklistItem[]) => void;
}) {
  const [draft, setDraft] = React.useState("");
  const [showDone, setShowDone] = React.useState(true);
  const inputs = React.useRef(new Map<string, HTMLInputElement>());
  const newRef = React.useRef<HTMLInputElement>(null);
  const focusNext = React.useRef<string | null>(null);
  // Stable id so the server-rendered (deep-linked) editor hydrates without a mismatch.
  const dndId = React.useId();

  const open = items.filter((i) => !i.done);
  const done = items.filter((i) => i.done);
  const full = items.length >= CHECKLIST_MAX;

  React.useEffect(() => {
    if (focusNext.current) {
      inputs.current.get(focusNext.current)?.focus();
      focusNext.current = null;
    }
  });

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  function patch(id: string, p: Partial<ChecklistItem>) {
    onChange(items.map((i) => (i.id === id ? { ...i, ...p } : i)));
  }

  function remove(id: string) {
    const idx = open.findIndex((i) => i.id === id);
    onChange(items.filter((i) => i.id !== id));
    if (idx > 0) focusNext.current = open[idx - 1].id;
  }

  function insertAfter(id: string) {
    if (full) return;
    const item = { id: newItemId(), text: "", done: false };
    const at = items.findIndex((i) => i.id === id);
    onChange([...items.slice(0, at + 1), item, ...items.slice(at + 1)]);
    focusNext.current = item.id;
  }

  function addNew() {
    const text = draft.trim();
    if (!text || full) return;
    // New items go after the last unticked one (ticked items stay at the bottom).
    const lastOpen = items.reduce((acc, it, i) => (it.done ? acc : i), -1);
    const item = { id: newItemId(), text, done: false };
    onChange([...items.slice(0, lastOpen + 1), item, ...items.slice(lastOpen + 1)]);
    setDraft("");
  }

  function onDragEnd(e: DragEndEvent) {
    const { active, over } = e;
    if (!over || active.id === over.id) return;
    const from = items.findIndex((i) => i.id === active.id);
    const to = items.findIndex((i) => i.id === over.id);
    if (from < 0 || to < 0) return;
    onChange(arrayMove(items, from, to));
  }

  return (
    <div className="space-y-1">
      <DndContext id={dndId} sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd} modifiers={[restrictToVerticalAxisModifier]}>
        <SortableContext items={open.map((i) => i.id)} strategy={verticalListSortingStrategy}>
          <ul className="space-y-0.5">
            {open.map((item) => (
              <Row
                key={item.id}
                item={item}
                sortable
                inputRef={(el) => {
                  if (el) inputs.current.set(item.id, el);
                  else inputs.current.delete(item.id);
                }}
                onToggle={() => patch(item.id, { done: true })}
                onText={(text) => patch(item.id, { text })}
                onRemove={() => remove(item.id)}
                onEnter={() => insertAfter(item.id)}
              />
            ))}
          </ul>
        </SortableContext>
      </DndContext>

      {!full ? (
        <div className="flex items-center gap-2 px-1">
          <Plus className="ml-5 h-4 w-4 shrink-0 text-muted" />
          <input
            ref={newRef}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                addNew();
              }
            }}
            onBlur={addNew}
            maxLength={CHECKLIST_TEXT_MAX}
            placeholder="Item checklist baru"
            aria-label="Tambah item checklist"
            className="h-8 min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-muted-soft"
          />
        </div>
      ) : (
        <p className="px-1 text-xs text-muted">Maksimal {CHECKLIST_MAX} item.</p>
      )}

      {done.length > 0 && (
        <div className="border-t border-black/10 pt-1">
          <div className="flex items-center justify-between gap-2">
            <button
              type="button"
              onClick={() => setShowDone((v) => !v)}
              className="flex items-center gap-1 rounded px-1 py-1 text-xs font-medium text-muted hover:text-foreground"
              aria-expanded={showDone}
            >
              {showDone ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
              {done.length} selesai
            </button>
            <button
              type="button"
              onClick={() => onChange(items.filter((i) => !i.done))}
              className="flex items-center gap-1 rounded px-1.5 py-1 text-xs font-medium text-muted hover:bg-black/5 hover:text-expense"
            >
              <Trash2 className="h-3.5 w-3.5" /> Hapus yang dicentang
            </button>
          </div>
          {showDone && (
            <ul className="space-y-0.5">
              {done.map((item) => (
                <Row
                  key={item.id}
                  item={item}
                  inputRef={() => {}}
                  onToggle={() => patch(item.id, { done: false })}
                  onText={(text) => patch(item.id, { text })}
                  onRemove={() => remove(item.id)}
                  onEnter={() => {}}
                />
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

function Row({
  item,
  sortable,
  inputRef,
  onToggle,
  onText,
  onRemove,
  onEnter,
}: {
  item: ChecklistItem;
  sortable?: boolean;
  inputRef: (el: HTMLInputElement | null) => void;
  onToggle: () => void;
  onText: (t: string) => void;
  onRemove: () => void;
  onEnter: () => void;
}) {
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, transition, isDragging } = useSortable({
    id: item.id,
    disabled: !sortable,
  });
  return (
    <li
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition }}
      className={cn("group flex items-center gap-1.5 rounded-md px-1", isDragging && "relative z-10 bg-white/80 shadow")}
    >
      {sortable ? (
        <button
          type="button"
          ref={setActivatorNodeRef}
          {...attributes}
          {...listeners}
          aria-label={`Geser "${item.text || "item"}"`}
          className="cursor-grab touch-none rounded p-0.5 text-muted-soft opacity-60 hover:text-foreground group-hover:opacity-100 focus-visible:opacity-100"
        >
          <GripVertical className="h-4 w-4" />
        </button>
      ) : (
        <span className="w-5" />
      )}
      <input
        type="checkbox"
        checked={item.done}
        onChange={onToggle}
        aria-label={item.done ? `Batalkan centang ${item.text}` : `Centang ${item.text}`}
        className="h-4 w-4 shrink-0 cursor-pointer accent-primary"
      />
      <input
        ref={inputRef}
        value={item.text}
        onChange={(e) => onText(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            onEnter();
          } else if (e.key === "Backspace" && !item.text) {
            e.preventDefault();
            onRemove();
          }
        }}
        maxLength={CHECKLIST_TEXT_MAX}
        aria-label="Teks item"
        className={cn("h-8 min-w-0 flex-1 bg-transparent text-sm outline-none", item.done && "text-muted line-through")}
      />
      <button
        type="button"
        onClick={onRemove}
        aria-label={`Hapus ${item.text || "item"}`}
        className="rounded p-1 text-muted-soft opacity-0 transition hover:bg-black/5 hover:text-expense group-hover:opacity-100 focus-visible:opacity-100"
      >
        <X className="h-3.5 w-3.5" />
      </button>
    </li>
  );
}
