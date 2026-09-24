"use client";

import * as React from "react";
import Link from "next/link";
import {
  AlertCircle,
  Archive,
  ArchiveRestore,
  ArrowRightLeft,
  Check,
  CheckSquare,
  Clapperboard,
  ExternalLink,
  FileAudio,
  ImagePlus,
  Link2,
  ListTodo,
  Loader2,
  Mic,
  MoreHorizontal,
  Palette,
  Pin,
  Plus,
  Receipt,
  Tag,
  Trash2,
  X,
} from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import {
  NOTE_COLORS,
  NOTE_LINKS_MAX,
  NOTE_TITLE_MAX,
  extractUrls,
  isHttpUrl,
  type ChecklistItem,
  type NoteColorId,
} from "@/lib/notes";
import { cn } from "@/lib/utils";
import { createNote, deleteNote, updateNote, type NoteInput } from "./actions";
import { BodyEditor } from "./body-editor";
import { ChecklistEditor } from "./checklist-editor";
import { ConvertDialog, type ConvertKind } from "./convert-dialogs";
import { LabelChip, LabelPicker } from "./labels";
import { NoteAudio, NotePhotos, RecorderProvider, canRecord } from "./note-media";
import {
  formatEdited,
  hostOf,
  isBlankNote,
  newItemId,
  noteBg,
  type ConvertContext,
  type NoteDTO,
  type NoteLabelDTO,
  type PushToast,
} from "./shared";
import { LinkPendingIcon } from "@/components/link-pending";

type Draft = {
  title: string;
  body: string;
  checklist: ChecklistItem[];
  labels: string[];
  color: NoteColorId | null;
  pinned: boolean;
  archived: boolean;
};
type Key = keyof Draft;
type Status = "idle" | "pending" | "saving" | "saved" | "error";

const SAVE_DELAY = 700;

function draftOf(n: NoteDTO | undefined, defaults: Partial<Draft>): Draft {
  return {
    title: n?.title ?? "",
    body: n?.body ?? "",
    checklist: n?.checklist ?? [],
    labels: n?.labels ?? defaults.labels ?? [],
    color: (n?.color as NoteColorId | null) ?? defaults.color ?? null,
    pinned: n?.pinned ?? false,
    archived: n?.archived ?? false,
  };
}

function toInput(d: Draft, keys: readonly Key[]): NoteInput {
  const out: NoteInput = {};
  for (const k of keys) {
    if (k === "title") out.title = d.title.trim() ? d.title : null;
    else (out as Record<string, unknown>)[k] = d[k];
  }
  return out;
}

/**
 * Note editor dialog with autosave (docs/notes.md). Only the fields the user touched in
 * this session are sent (a patch), so edits made meanwhile on another device to other
 * fields are kept; untouched fields follow the server. Saves are serialized (one request
 * at a time) and debounced; closing flushes. A note is created on the first real content
 * (an untouched "new note" never hits the server) and deleted again if it is left blank.
 */
export function NoteEditor({
  noteId,
  note,
  defaults,
  labels,
  ctx,
  toast,
  onCreated,
  onClose,
  onDelete,
}: {
  noteId: string | null;
  /** Server copy (undefined for a new note until it exists). */
  note: NoteDTO | undefined;
  defaults: Partial<Draft>;
  labels: NoteLabelDTO[];
  ctx: ConvertContext;
  toast: PushToast;
  onCreated: (id: string) => void;
  onClose: () => void;
  /** Deletes the note (optimistically, with the page's pending hint) once `after` settles. */
  onDelete?: (id: string, after: Promise<unknown>) => void;
}) {
  const [local, setLocal] = React.useState<Partial<Draft>>(() => (noteId ? {} : { ...defaults }));
  const [status, setStatus] = React.useState<Status>("idle");
  const [picker, setPicker] = React.useState<null | "labels" | "colors" | "convert" | "more">(null);
  const [convert, setConvert] = React.useState<ConvertKind | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const [showChecklist, setShowChecklist] = React.useState(false);
  const [linkDraft, setLinkDraft] = React.useState<string | null>(null);

  const base = React.useMemo(() => draftOf(note, defaults), [note, defaults]);
  const value: Draft = { ...base, ...local };

  const idRef = React.useRef<string | null>(noteId);
  const createdHere = React.useRef(false);
  const keep = React.useRef(false);
  const localRef = React.useRef(local);
  const baseRef = React.useRef(base);
  const noteRef = React.useRef(note);
  // Links as last written by this editor — a second add/remove before the page refreshes
  // must build on the first, not on the stale server copy. Reset when fresh data arrives.
  const linksRef = React.useRef<NoteDTO["links"] | null>(null);
  const dirty = React.useRef(new Set<Key>());
  const chain = React.useRef<Promise<void>>(Promise.resolve());
  const timer = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const failed = React.useRef(false);
  const toastRef = React.useRef(toast);
  const onCreatedRef = React.useRef(onCreated);
  React.useEffect(() => {
    baseRef.current = base;
    noteRef.current = note;
    toastRef.current = toast;
    onCreatedRef.current = onCreated;
  });
  const serverLinks = note?.links;
  React.useEffect(() => {
    linksRef.current = null;
  }, [serverLinks]);

  const photoPick = React.useRef<HTMLInputElement>(null);
  const audioPick = React.useRef<HTMLInputElement>(null);
  const recorder = React.useRef<{ start: () => void } | null>(null);
  const titleRef = React.useRef<HTMLInputElement>(null);

  /** Queue a save of the dirty fields (or a create). Resolves when it has run. */
  const flush = React.useCallback((forceCreate = false): Promise<void> => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
    const run = async () => {
      const keys = [...dirty.current];
      const d = { ...baseRef.current, ...localRef.current };
      if (!idRef.current) {
        if (!forceCreate && isBlankNote({ ...d, title: d.title || null })) {
          setStatus("idle");
          return;
        }
        dirty.current.clear();
        setStatus("saving");
        const res = await createNote(toInput(d, ["title", "body", "checklist", "labels", "color", "pinned", "archived"])).catch(() => ({
          ok: false as const,
          error: "Gagal menyimpan. Periksa koneksi.",
        }));
        if (res.ok) {
          idRef.current = res.id;
          createdHere.current = true;
          failed.current = false;
          onCreatedRef.current(res.id);
          setStatus(dirty.current.size ? "pending" : "saved");
        } else {
          keys.forEach((k) => dirty.current.add(k));
          if (!failed.current) toastRef.current({ text: res.error, tone: "error" });
          failed.current = true;
          setStatus("error");
        }
        return;
      }
      if (!keys.length) return;
      dirty.current.clear();
      setStatus("saving");
      const res = await updateNote(idRef.current, toInput(d, keys)).catch(() => ({
        ok: false as const,
        error: "Gagal menyimpan. Periksa koneksi.",
      }));
      if (res.ok) {
        failed.current = false;
        setStatus(dirty.current.size ? "pending" : "saved");
      } else {
        keys.forEach((k) => dirty.current.add(k));
        if (!failed.current) toastRef.current({ text: res.error, tone: "error" });
        failed.current = true;
        setStatus("error");
      }
    };
    chain.current = chain.current.then(run, run);
    return chain.current;
  }, []);

  const change = React.useCallback(
    (patch: Partial<Draft>, immediate = false) => {
      localRef.current = { ...localRef.current, ...patch };
      setLocal(localRef.current);
      for (const k of Object.keys(patch) as Key[]) dirty.current.add(k);
      setStatus("pending");
      if (timer.current) clearTimeout(timer.current);
      if (immediate) void flush();
      else timer.current = setTimeout(() => void flush(), SAVE_DELAY);
    },
    [flush],
  );

  /** The note's id — creating it (even blank) when needed, e.g. before an upload. */
  const ensureId = React.useCallback(async () => {
    // Something is being attached (photo, clip, link, conversion) — possibly still in
    // flight when the editor closes — so never discard this note as "blank" on close.
    keep.current = true;
    await flush(true);
    return idRef.current;
  }, [flush]);

  const close = React.useCallback(() => {
    onClose();
    void (async () => {
      const failedBefore = failed.current;
      await flush();
      // The final save failed again: flush doesn't repeat its error toast within a failure
      // streak, so say it here — the editor is gone and the edit is not saved.
      if (failedBefore && failed.current && dirty.current.size) {
        toastRef.current({ text: "Perubahan terakhir gagal disimpan. Periksa koneksi lalu edit lagi.", tone: "error" });
        return;
      }
      const id = idRef.current;
      const n = noteRef.current;
      const d = { ...baseRef.current, ...localRef.current };
      if (id && createdHere.current && !keep.current && isBlankNote({ ...d, title: d.title || null, photos: n?.photos, audio: n?.audio })) {
        await deleteNote(id).catch(() => null);
        toastRef.current({ text: "Catatan kosong dibuang", tone: "info" });
      }
    })();
  }, [flush, onClose]);

  const subOpen = convert !== null || confirmDelete;

  // Esc closes (unless a nested dialog/popover is open), Ctrl/Cmd+S saves now.
  React.useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !subOpen) {
        if (picker) setPicker(null);
        else close();
      } else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        void flush();
      }
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [close, flush, picker, subOpen]);

  // Lock page scroll while open.
  React.useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, []);

  // Warn before leaving the page with unsaved edits.
  React.useEffect(() => {
    if (status !== "pending" && status !== "saving" && status !== "error") return;
    const h = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener("beforeunload", h);
    return () => window.removeEventListener("beforeunload", h);
  }, [status]);

  // Focus the title of a fresh note.
  React.useEffect(() => {
    if (!noteId) titleRef.current?.focus();
  }, [noteId]);

  const currentId = noteId;
  const photos = note?.photos ?? [];
  const audio = note?.audio ?? [];
  const links = note?.links ?? [];
  const bodyUrls = React.useMemo(() => new Set(extractUrls(value.body)), [value.body]);
  const labelById = React.useMemo(() => new Map(labels.map((l) => [l.id, l])), [labels]);
  const checklistVisible = showChecklist || value.checklist.length > 0;

  function enqueue(fn: () => Promise<{ ok: boolean; error?: string }>) {
    chain.current = chain.current.then(async () => {
      const res = await fn().catch(() => ({ ok: false, error: "Terjadi kesalahan, coba lagi" }));
      if (!res.ok) toast({ text: res.error ?? "Gagal menyimpan", tone: "error" });
    });
    return chain.current;
  }

  async function addLink() {
    const url = (linkDraft ?? "").trim();
    const full = /^https?:\/\//i.test(url) ? url : `https://${url}`;
    if (!isHttpUrl(full)) return toast({ text: "Tautan harus berupa URL http(s) yang valid", tone: "error" });
    if (links.some((l) => l.url === full)) return setLinkDraft(null);
    const id = await ensureId();
    if (!id) return;
    setLinkDraft(null);
    await enqueue(() => writeLinks(id, (ls) => (ls.some((l) => l.url === full) ? ls : [...ls, { url: full, title: null }])));
  }

  function removeLink(url: string) {
    if (!currentId) return;
    const id = currentId;
    void enqueue(() => writeLinks(id, (ls) => ls.filter((l) => l.url !== url)));
  }

  /** Save `edit(latest links)`; runs inside the save chain so edits apply in order. */
  async function writeLinks(id: string, edit: (ls: NoteDTO["links"]) => NoteDTO["links"]) {
    const server = noteRef.current?.links ?? [];
    const titles = new Map(server.map((l) => [l.url, l.title]));
    const latest = (linksRef.current ?? server).map((l) => ({ ...l, title: l.title ?? titles.get(l.url) ?? null }));
    const next = edit(latest);
    const res = await updateNote(id, { links: next });
    if (res.ok) linksRef.current = next;
    return res;
  }

  function insertIntoBody(text: string) {
    const body = value.body.trim() ? `${value.body.replace(/\s+$/, "")}\n\n${text}` : text;
    change({ body });
  }

  const bg = noteBg(value.color);

  return (
    <RecorderProvider apiRef={recorder}>
      <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-4">
        <div className="absolute inset-0 bg-slate-900/40 backdrop-blur-sm animate-fade-in" onClick={() => !subOpen && close()} />
        <div
          role="dialog"
          aria-modal="true"
          aria-label={noteId ? "Edit catatan" : "Catatan baru"}
          className="relative z-10 flex max-h-[94dvh] w-full flex-col overflow-hidden rounded-t-2xl bg-card shadow-xl animate-fade-in sm:max-h-[90vh] sm:max-w-2xl sm:rounded-2xl"
          style={bg ? { background: bg } : undefined}
        >
          {/* Header */}
          <div className="flex items-center gap-2 px-4 pb-1 pt-3 sm:px-5">
            <SaveStatus status={status} onRetry={() => void flush()} />
            <div className="flex-1" />
            <IconButton
              label={value.pinned ? "Lepas sematan" : "Sematkan"}
              active={value.pinned}
              onClick={() => change({ pinned: !value.pinned }, true)}
            >
              <Pin className={cn("h-[18px] w-[18px]", value.pinned && "fill-current")} />
            </IconButton>
            <IconButton label="Tutup" onClick={close}>
              <X className="h-5 w-5" />
            </IconButton>
          </div>

          {/* Scrollable content */}
          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-4 pb-4 sm:px-5">
            <input
              ref={titleRef}
              value={value.title}
              onChange={(e) => change({ title: e.target.value })}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  (e.currentTarget.closest("[role=dialog]")?.querySelector("textarea") as HTMLTextAreaElement | null)?.focus();
                }
              }}
              maxLength={NOTE_TITLE_MAX}
              placeholder="Judul"
              aria-label="Judul catatan"
              className="w-full bg-transparent text-lg font-semibold text-foreground outline-none placeholder:text-muted-soft"
            />

            <BodyEditor value={value.body} onChange={(body) => change({ body })} />

            {checklistVisible && (
              <section aria-label="Checklist">
                <SectionTitle>Checklist</SectionTitle>
                <ChecklistEditor items={value.checklist} onChange={(checklist) => change({ checklist })} />
              </section>
            )}

            <NotePhotos
              ensureId={ensureId}
              noteId={currentId}
              photos={photos}
              audio={audio}
              toast={toast}
              onInsertText={insertIntoBody}
              pickRef={photoPick}
            />

            <NoteAudio
              ensureId={ensureId}
              noteId={currentId}
              photos={photos}
              audio={audio}
              toast={toast}
              onInsertText={insertIntoBody}
              pickRef={audioPick}
            />

            {(links.length > 0 || linkDraft !== null) && (
              <section aria-label="Tautan">
                <SectionTitle>Tautan</SectionTitle>
                <ul className="space-y-1.5">
                  {links.map((l) => (
                    <li key={l.url} className="group flex items-center gap-2 rounded-lg border border-black/10 bg-white/50 px-2.5 py-2">
                      <Link2 className="h-4 w-4 shrink-0 text-muted" />
                      <a href={l.url} target="_blank" rel="noopener noreferrer" className="min-w-0 flex-1 hover:underline">
                        <span className="block truncate text-sm font-medium text-foreground">{l.title || hostOf(l.url)}</span>
                        <span className="block truncate text-xs text-muted">{l.url}</span>
                      </a>
                      <ExternalLink className="h-3.5 w-3.5 shrink-0 text-muted" aria-hidden />
                      {bodyUrls.has(l.url) ? (
                        <span className="shrink-0 text-[11px] text-muted-soft" title="Tautan ini ada di isi catatan">
                          dari isi
                        </span>
                      ) : (
                        <button
                          type="button"
                          onClick={() => removeLink(l.url)}
                          aria-label={`Hapus tautan ${l.url}`}
                          className="shrink-0 rounded p-1 text-muted hover:bg-black/5 hover:text-expense"
                        >
                          <X className="h-3.5 w-3.5" />
                        </button>
                      )}
                    </li>
                  ))}
                </ul>
                {linkDraft !== null && (
                  <form
                    className="mt-2 flex gap-2"
                    onSubmit={(e) => {
                      e.preventDefault();
                      void addLink();
                    }}
                  >
                    <input
                      autoFocus
                      value={linkDraft}
                      onChange={(e) => setLinkDraft(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Escape") {
                          e.nativeEvent.stopImmediatePropagation();
                          setLinkDraft(null);
                        }
                      }}
                      placeholder="https://…"
                      aria-label="URL tautan"
                      inputMode="url"
                      className="h-9 min-w-0 flex-1 rounded-lg border border-black/10 bg-white/70 px-2.5 text-sm outline-none focus:border-primary"
                    />
                    <Button type="submit" size="sm" className="h-9">
                      Tambah
                    </Button>
                    <Button type="button" size="sm" variant="ghost" className="h-9" onClick={() => setLinkDraft(null)}>
                      Batal
                    </Button>
                  </form>
                )}
              </section>
            )}

            {value.labels.length > 0 && (
              <div className="flex flex-wrap gap-1.5" aria-label="Label">
                {value.labels.map((id) => {
                  const l = labelById.get(id);
                  return l ? <LabelChip key={id} label={l} onClick={() => setPicker("labels")} /> : null;
                })}
              </div>
            )}

            <LinkedRow note={note} />

            {note && (
              <p className="text-right text-xs text-muted" suppressHydrationWarning>
                Diedit {formatEdited(note.updatedAt)}
              </p>
            )}
          </div>

          {/* Toolbar */}
          <div className="relative flex items-center gap-0.5 border-t border-black/10 px-2 py-2 sm:px-3">
            <div className="relative">
              <IconButton label="Warna" active={picker === "colors"} onClick={() => setPicker(picker === "colors" ? null : "colors")}>
                <Palette className="h-[18px] w-[18px]" />
              </IconButton>
              {picker === "colors" && (
                <Popover onClose={() => setPicker(null)} label="Pilih warna">
                  <div className="grid grid-cols-6 gap-1.5">
                    <Swatch label="Default" selected={!value.color} onClick={() => change({ color: null }, true)} />
                    {NOTE_COLORS.map((c) => (
                      <Swatch key={c.id} label={c.label} color={c.light} selected={value.color === c.id} onClick={() => change({ color: c.id }, true)} />
                    ))}
                  </div>
                </Popover>
              )}
            </div>
            <div className="relative">
              <IconButton label="Label" active={picker === "labels"} onClick={() => setPicker(picker === "labels" ? null : "labels")}>
                <Tag className="h-[18px] w-[18px]" />
              </IconButton>
              {picker === "labels" && (
                <LabelPicker
                  labels={labels}
                  selected={value.labels}
                  onChange={(ids) => change({ labels: ids }, true)}
                  toast={toast}
                  onClose={() => setPicker(null)}
                />
              )}
            </div>
            <IconButton
              label="Checklist"
              active={checklistVisible}
              onClick={() => {
                if (!checklistVisible) {
                  setShowChecklist(true);
                  if (!value.checklist.length) change({ checklist: [{ id: newItemId(), text: "", done: false }] });
                }
              }}
            >
              <CheckSquare className="h-[18px] w-[18px]" />
            </IconButton>
            <IconButton label="Tambah foto" onClick={() => photoPick.current?.click()}>
              <ImagePlus className="h-[18px] w-[18px]" />
            </IconButton>
            <div className="relative">
              <IconButton label="Lainnya" active={picker === "more"} onClick={() => setPicker(picker === "more" ? null : "more")}>
                <MoreHorizontal className="h-[18px] w-[18px]" />
              </IconButton>
              {picker === "more" && (
                <Popover onClose={() => setPicker(null)} label="Lainnya" menu>
                  <MenuItem icon={FileAudio} onClick={() => (setPicker(null), audioPick.current?.click())}>
                    Unggah rekaman suara
                  </MenuItem>
                  {canRecord() && (
                    <MenuItem icon={Mic} onClick={() => (setPicker(null), recorder.current?.start())}>
                      Rekam suara
                    </MenuItem>
                  )}
                  <MenuItem
                    icon={Link2}
                    disabled={links.length >= NOTE_LINKS_MAX}
                    onClick={() => (setPicker(null), setLinkDraft(""))}
                  >
                    Tambah tautan
                  </MenuItem>
                  <MenuItem
                    icon={value.archived ? ArchiveRestore : Archive}
                    onClick={() => {
                      setPicker(null);
                      const archived = !value.archived;
                      change({ archived }, true);
                      if (archived) {
                        close();
                        toast({ text: "Catatan diarsipkan", tone: "success" });
                      }
                    }}
                  >
                    {value.archived ? "Keluarkan dari arsip" : "Arsipkan"}
                  </MenuItem>
                  <MenuItem
                    icon={Trash2}
                    danger
                    onClick={() => {
                      setPicker(null);
                      if (currentId) setConfirmDelete(true);
                      else close();
                    }}
                  >
                    Hapus catatan
                  </MenuItem>
                </Popover>
              )}
            </div>
            <div className="relative">
              <button
                type="button"
                onClick={() => setPicker(picker === "convert" ? null : "convert")}
                aria-expanded={picker === "convert"}
                aria-haspopup="menu"
                className={cn(
                  "ml-1 flex h-9 items-center gap-1.5 rounded-lg px-2.5 text-sm font-medium text-foreground/80 transition hover:bg-black/5",
                  picker === "convert" && "bg-black/5",
                )}
              >
                <ArrowRightLeft className="h-4 w-4" />
                <span className="hidden sm:inline">Jadikan…</span>
              </button>
              {picker === "convert" && (
                <Popover onClose={() => setPicker(null)} label="Jadikan" menu>
                  <MenuItem icon={ListTodo} done={!!note?.linkedTaskId} onClick={() => (setPicker(null), setConvert("task"))}>
                    Tugas
                  </MenuItem>
                  <MenuItem icon={Clapperboard} done={!!note?.linkedContentId} onClick={() => (setPicker(null), setConvert("content"))}>
                    Konten
                  </MenuItem>
                  <MenuItem icon={Receipt} done={!!note?.linkedTransactionId} onClick={() => (setPicker(null), setConvert("transaction"))}>
                    Transaksi
                  </MenuItem>
                </Popover>
              )}
            </div>
            <div className="flex-1" />
            <Button size="sm" onClick={close}>
              Selesai
            </Button>
          </div>
        </div>
      </div>

      <ConvertDialog
        kind={convert}
        noteId={currentId}
        ctx={ctx}
        ensureSaved={ensureId}
        onClose={() => setConvert(null)}
        toast={toast}
      />

      <Modal open={confirmDelete} onClose={() => setConfirmDelete(false)} title="Hapus catatan?">
        <p className="text-sm text-muted">
          Catatan ini beserta foto dan rekamannya dihapus permanen. Pilih <strong>Arsipkan</strong> kalau hanya ingin
          menyembunyikannya.
        </p>
        <div className="mt-5 flex justify-end gap-2">
          <Button variant="ghost" onClick={() => setConfirmDelete(false)}>
            Batal
          </Button>
          <Button
            variant="danger"
            onClick={async () => {
              const id = idRef.current;
              setConfirmDelete(false);
              if (timer.current) clearTimeout(timer.current);
              dirty.current.clear();
              onClose();
              if (!id) return;
              if (onDelete) return onDelete(id, chain.current);
              await chain.current;
              const res = await deleteNote(id).catch(() => ({ ok: false as const, error: "Gagal menghapus catatan" }));
              toast(res.ok ? { text: "Catatan dihapus", tone: "success" } : { text: res.error, tone: "error" });
            }}
          >
            Hapus
          </Button>
        </div>
      </Modal>
    </RecorderProvider>
  );
}

function SaveStatus({ status, onRetry }: { status: Status; onRetry: () => void }) {
  if (status === "idle") return <span className="text-xs text-muted-soft">Tersimpan otomatis</span>;
  if (status === "error")
    return (
      <button type="button" onClick={onRetry} className="flex items-center gap-1 text-xs font-medium text-expense hover:underline">
        <AlertCircle className="h-3.5 w-3.5" /> Gagal menyimpan · Coba lagi
      </button>
    );
  if (status === "saved")
    return (
      <span className="flex items-center gap-1 text-xs text-muted" role="status">
        <Check className="h-3.5 w-3.5 text-income" /> Tersimpan
      </span>
    );
  return (
    <span className="flex items-center gap-1 text-xs text-muted" role="status">
      <Loader2 className="h-3.5 w-3.5 animate-spin" /> Menyimpan…
    </span>
  );
}

function LinkedRow({ note }: { note: NoteDTO | undefined }) {
  if (!note || (!note.linkedTaskId && !note.linkedContentId && !note.linkedTransactionId)) return null;
  const cls =
    "inline-flex items-center gap-1.5 rounded-full bg-white/70 px-2.5 py-1 text-xs font-medium text-primary ring-1 ring-black/5 hover:bg-white";
  return (
    <div className="flex flex-wrap gap-1.5">
      {note.linkedTaskId && (
        <Link href="/tasks" className={cls}>
          <LinkPendingIcon className="h-3.5 w-3.5"><ListTodo className="h-3.5 w-3.5" /></LinkPendingIcon> Sudah jadi tugas →
        </Link>
      )}
      {note.linkedContentId && (
        <Link href={`/content?item=${encodeURIComponent(note.linkedContentId)}`} className={cls}>
          <LinkPendingIcon className="h-3.5 w-3.5"><Clapperboard className="h-3.5 w-3.5" /></LinkPendingIcon> Sudah jadi konten →
        </Link>
      )}
      {note.linkedTransactionId && (
        <Link href="/transactions" className={cls}>
          <LinkPendingIcon className="h-3.5 w-3.5"><Receipt className="h-3.5 w-3.5" /></LinkPendingIcon> Sudah dicatat sebagai transaksi →
        </Link>
      )}
    </div>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return <h3 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted">{children}</h3>;
}

function IconButton({
  label,
  active,
  onClick,
  children,
}: {
  label: string;
  active?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={label}
      aria-label={label}
      aria-pressed={active}
      className={cn(
        "flex h-9 w-9 shrink-0 items-center justify-center rounded-lg transition hover:bg-black/5",
        active ? "text-primary" : "text-foreground/70",
      )}
    >
      {children}
    </button>
  );
}

function Popover({ children, onClose, label, menu }: { children: React.ReactNode; onClose: () => void; label: string; menu?: boolean }) {
  const ref = React.useRef<HTMLDivElement>(null);
  React.useEffect(() => {
    function onDown(e: PointerEvent) {
      const t = e.target as Node;
      // Clicks on the popover's own toggle button are handled by the button.
      if (ref.current && !ref.current.parentElement?.contains(t)) onClose();
    }
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [onClose]);
  return (
    <div
      ref={ref}
      role={menu ? "menu" : "dialog"}
      aria-label={label}
      className="absolute bottom-full left-0 z-20 mb-2 min-w-48 max-w-[calc(100vw-2rem)] rounded-xl border border-border bg-card p-1.5 text-foreground shadow-xl"
    >
      {children}
    </div>
  );
}

function MenuItem({
  icon: Icon,
  children,
  onClick,
  danger,
  done,
  disabled,
}: {
  icon: React.ComponentType<{ className?: string }>;
  children: React.ReactNode;
  onClick: () => void;
  danger?: boolean;
  done?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="menuitem"
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "flex w-full items-center gap-2.5 whitespace-nowrap rounded-lg px-2.5 py-2 text-left text-sm transition hover:bg-accent disabled:opacity-40",
        danger ? "text-expense" : "text-foreground",
      )}
    >
      <Icon className="h-4 w-4 shrink-0" />
      <span className="flex-1">{children}</span>
      {done && <Check className="h-4 w-4 text-income" aria-label="sudah" />}
    </button>
  );
}

function Swatch({ label, color, selected, onClick }: { label: string; color?: string; selected: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={label}
      aria-label={label}
      aria-pressed={selected}
      className={cn(
        "flex h-8 w-8 items-center justify-center rounded-full border transition hover:scale-110",
        selected ? "border-primary ring-2 ring-primary/40" : "border-black/15",
        !color && "bg-card",
      )}
      style={color ? { background: color } : undefined}
    >
      {selected ? <Check className="h-4 w-4 text-foreground/70" /> : !color ? <Plus className="h-4 w-4 rotate-45 text-muted" /> : null}
    </button>
  );
}
