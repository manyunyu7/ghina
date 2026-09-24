"use client";

import * as React from "react";
import { Archive, ArchiveRestore, Clapperboard, Link2, ListTodo, Mic, Palette, Pin, Receipt, Trash2 } from "lucide-react";
import { NOTE_COLORS, type NoteColorId } from "@/lib/notes";
import { cn } from "@/lib/utils";
import { LabelChip } from "./labels";
import { Markdown } from "./markdown";
import { formatDuration, hostOf, noteBg, type NoteDTO, type NoteLabelDTO } from "./shared";

const PREVIEW_ITEMS = 6;

export type CardActions = {
  open: (id: string) => void;
  pin: (n: NoteDTO) => void;
  archive: (n: NoteDTO) => void;
  color: (n: NoteDTO, c: NoteColorId | null) => void;
  toggleItem: (n: NoteDTO, itemId: string) => void;
  remove: (n: NoteDTO) => void;
  filterLabel: (labelId: string) => void;
};

export function NoteCard({
  note,
  labels,
  actions,
  list,
}: {
  note: NoteDTO;
  labels: Map<string, NoteLabelDTO>;
  actions: CardActions;
  list?: boolean;
}) {
  const [palette, setPalette] = React.useState(false);
  const bg = noteBg(note.color);
  const open = note.checklist.filter((i) => !i.done);
  const doneCount = note.checklist.length - open.length;
  const total = note.checklist.length;
  const audioSec = note.audio.reduce((s, a) => s + a.durationSec, 0);
  const title = note.title?.trim();
  const body = note.body.trim();
  const empty = !title && !body && total === 0 && !note.photos.length && !note.audio.length;
  const bodyPreview = body.length > 700 ? `${body.slice(0, 700)}…` : body;

  function stop(e: React.SyntheticEvent) {
    e.stopPropagation();
  }

  return (
    <article
      tabIndex={0}
      role="button"
      aria-label={title || "Catatan tanpa judul"}
      onClick={() => actions.open(note.id)}
      onKeyDown={(e) => {
        if ((e.key === "Enter" || e.key === " ") && e.target === e.currentTarget) {
          e.preventDefault();
          actions.open(note.id);
        }
      }}
      className={cn(
        "group relative mb-4 w-full cursor-pointer break-inside-avoid rounded-card border text-left shadow-sm outline-none transition hover:shadow-md focus-visible:ring-2 focus-visible:ring-primary/50",
        bg ? "border-black/5" : "border-border bg-card",
      )}
      style={bg ? { background: bg } : undefined}
    >
      {note.photos.length > 0 && (
        <div className="relative overflow-hidden rounded-t-card">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={note.photos[0]} alt="" loading="lazy" decoding="async" className={cn("w-full object-cover", list ? "max-h-40" : "max-h-56")} />
          {note.photos.length > 1 && (
            <span className="absolute bottom-2 right-2 rounded-full bg-slate-900/60 px-2 py-0.5 text-xs font-medium text-white">
              +{note.photos.length - 1} foto
            </span>
          )}
        </div>
      )}

      <div className="space-y-2 p-4">
        <div className="flex items-start gap-2">
          {title ? (
            <h3 className="min-w-0 flex-1 break-words text-[15px] font-semibold leading-snug text-foreground">{title}</h3>
          ) : (
            <div className="flex-1" />
          )}
          <button
            type="button"
            onClick={(e) => {
              stop(e);
              actions.pin(note);
            }}
            aria-label={note.pinned ? "Lepas sematan" : "Sematkan"}
            title={note.pinned ? "Lepas sematan" : "Sematkan"}
            className={cn(
              "-mr-1 -mt-1 shrink-0 rounded-lg p-1.5 transition hover:bg-black/5",
              note.pinned ? "text-foreground/80" : "text-muted opacity-0 group-hover:opacity-100 focus-visible:opacity-100 max-sm:opacity-60",
            )}
          >
            <Pin className={cn("h-4 w-4", note.pinned && "fill-current")} />
          </button>
        </div>

        {body && (
          <div className="relative max-h-64 overflow-hidden">
            <Markdown text={bodyPreview} className="text-foreground/85" />
          </div>
        )}

        {total > 0 && (
          <div className="space-y-1">
            <ul className="space-y-0.5">
              {open.slice(0, PREVIEW_ITEMS).map((item) => (
                <li key={item.id} className="flex items-start gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={false}
                    onClick={stop}
                    onChange={() => actions.toggleItem(note, item.id)}
                    aria-label={`Centang ${item.text}`}
                    className="mt-0.5 h-4 w-4 shrink-0 cursor-pointer accent-primary"
                  />
                  <span className="min-w-0 break-words text-foreground/85">{item.text || <span className="text-muted-soft">(kosong)</span>}</span>
                </li>
              ))}
            </ul>
            {open.length > PREVIEW_ITEMS && <p className="pl-6 text-xs text-muted">+{open.length - PREVIEW_ITEMS} item lagi</p>}
            <div className="flex items-center gap-2 pt-1">
              <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-black/10">
                <div className="h-full rounded-full bg-income transition-all" style={{ width: `${(doneCount / total) * 100}%` }} />
              </div>
              <span className="text-xs tabular-nums text-muted">
                {doneCount}/{total}
              </span>
            </div>
          </div>
        )}

        {note.links.length > 0 && (
          <ul className="space-y-1">
            {note.links.slice(0, 2).map((l) => (
              <li key={l.url}>
                <a
                  href={l.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={stop}
                  className="flex items-center gap-2 rounded-lg bg-black/[0.04] px-2 py-1.5 hover:bg-black/[0.08]"
                >
                  <Link2 className="h-3.5 w-3.5 shrink-0 text-muted" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-xs font-medium text-foreground">{l.title || hostOf(l.url)}</span>
                    {l.title && <span className="block truncate text-[11px] text-muted">{hostOf(l.url)}</span>}
                  </span>
                </a>
              </li>
            ))}
            {note.links.length > 2 && <li className="text-xs text-muted">+{note.links.length - 2} tautan</li>}
          </ul>
        )}

        {empty && <p className="text-sm text-muted-soft">Catatan kosong</p>}

        {(note.labels.length > 0 || note.audio.length > 0 || note.linkedTaskId || note.linkedContentId || note.linkedTransactionId) && (
          <div className="flex flex-wrap items-center gap-1.5 pt-0.5">
            {note.audio.length > 0 && (
              <span className="inline-flex items-center gap-1 rounded-full bg-black/[0.06] px-2 py-0.5 text-xs font-medium text-foreground/80" title="Rekaman suara">
                <Mic className="h-3 w-3" />
                {note.audio.length > 1 ? `${note.audio.length} · ` : ""}
                {formatDuration(audioSec)}
              </span>
            )}
            {note.labels.map((id) => {
              const l = labels.get(id);
              return l ? <LabelChip key={id} label={l} onClick={() => actions.filterLabel(id)} /> : null;
            })}
            {note.linkedTaskId && <LinkedIcon icon={ListTodo} label="Sudah jadi tugas" />}
            {note.linkedContentId && <LinkedIcon icon={Clapperboard} label="Sudah jadi konten" />}
            {note.linkedTransactionId && <LinkedIcon icon={Receipt} label="Sudah dicatat sebagai transaksi" />}
          </div>
        )}
      </div>

      {/* Hover actions */}
      <div
        className="flex items-center gap-0.5 px-2 pb-2 opacity-0 transition group-hover:opacity-100 group-focus-within:opacity-100 max-sm:opacity-70"
        onClick={stop}
      >
        <div className="relative">
          <CardButton label="Ubah warna" onClick={() => setPalette((v) => !v)}>
            <Palette className="h-4 w-4" />
          </CardButton>
          {palette && (
            <ColorPop
              value={(note.color as NoteColorId | null) ?? null}
              onPick={(c) => {
                setPalette(false);
                actions.color(note, c);
              }}
              onClose={() => setPalette(false)}
            />
          )}
        </div>
        <CardButton label={note.archived ? "Keluarkan dari arsip" : "Arsipkan"} onClick={() => actions.archive(note)}>
          {note.archived ? <ArchiveRestore className="h-4 w-4" /> : <Archive className="h-4 w-4" />}
        </CardButton>
        <CardButton label="Hapus" onClick={() => actions.remove(note)}>
          <Trash2 className="h-4 w-4" />
        </CardButton>
      </div>
    </article>
  );
}

function LinkedIcon({ icon: Icon, label }: { icon: React.ComponentType<{ className?: string }>; label: string }) {
  return (
    <span title={label} aria-label={label} className="inline-flex items-center rounded-full bg-primary-soft p-1 text-primary">
      <Icon className="h-3 w-3" />
    </span>
  );
}

function CardButton({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className="rounded-lg p-1.5 text-foreground/60 transition hover:bg-black/5 hover:text-foreground"
    >
      {children}
    </button>
  );
}

function ColorPop({ value, onPick, onClose }: { value: NoteColorId | null; onPick: (c: NoteColorId | null) => void; onClose: () => void }) {
  const ref = React.useRef<HTMLDivElement>(null);
  React.useEffect(() => {
    function onDown(e: PointerEvent) {
      if (ref.current && !ref.current.parentElement?.contains(e.target as Node)) onClose();
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("pointerdown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [onClose]);
  return (
    <div ref={ref} role="dialog" aria-label="Pilih warna" className="absolute bottom-full left-0 z-20 mb-1 grid w-max grid-cols-6 gap-1 rounded-xl border border-border bg-card p-2 shadow-xl">
      <button
        type="button"
        onClick={() => onPick(null)}
        aria-label="Default"
        title="Default"
        className={cn("h-7 w-7 rounded-full border bg-card", !value ? "border-primary ring-2 ring-primary/40" : "border-black/15")}
      />
      {NOTE_COLORS.map((c) => (
        <button
          key={c.id}
          type="button"
          onClick={() => onPick(c.id)}
          aria-label={c.label}
          title={c.label}
          className={cn("h-7 w-7 rounded-full border", value === c.id ? "border-primary ring-2 ring-primary/40" : "border-black/15")}
          style={{ background: c.light }}
        />
      ))}
    </div>
  );
}
