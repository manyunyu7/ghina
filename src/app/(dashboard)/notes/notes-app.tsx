"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Archive, LayoutGrid, Rows3, Search, Settings2, StickyNote, Tag, X, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { SavingHint } from "@/components/ui/saving-hint";
import { compareNotes, noteMatches, type NoteColorId } from "@/lib/notes";
import { cn } from "@/lib/utils";
import { deleteNote, setNoteArchived, setNoteColor, setNotePinned, toggleChecklistItem } from "./actions";
import { LabelManager } from "./labels";
import { NoteCard, type CardActions } from "./note-card";
import { NoteEditor } from "./note-editor";
import { isTypingTarget, type AreaOption, type CategoryOption, type NoteDTO, type NoteLabelDTO, type WalletOption } from "./shared";
import { Toasts, useToasts } from "./toasts";

type Tab = "all" | "archive" | string;
type EditorState = { key: number; id: string | null; defaults: { labels?: string[] } };
type View = "grid" | "list";

// ---------- Grid/list preference (per browser) ----------

const VIEW_KEY = "ghina.notes.view";
const viewListeners = new Set<() => void>();
function readView(): View {
  try {
    return localStorage.getItem(VIEW_KEY) === "list" ? "list" : "grid";
  } catch {
    return "grid";
  }
}
function writeView(v: View) {
  try {
    localStorage.setItem(VIEW_KEY, v);
  } catch {
    // storage blocked: the choice just isn't remembered
  }
  viewListeners.forEach((l) => l());
}
function subscribeView(cb: () => void) {
  viewListeners.add(cb);
  window.addEventListener("storage", cb);
  return () => {
    viewListeners.delete(cb);
    window.removeEventListener("storage", cb);
  };
}

export function NotesApp({
  notes: serverNotes,
  labels,
  areas,
  wallets,
  categories,
  currency,
  initialNoteId,
}: {
  notes: NoteDTO[];
  labels: NoteLabelDTO[];
  areas: AreaOption[];
  wallets: WalletOption[];
  categories: CategoryOption[];
  currency: string;
  initialNoteId: string | null;
}) {
  const router = useRouter();
  const { toasts, push, dismiss } = useToasts();
  const [notes, applyOptimistic] = React.useOptimistic(serverNotes, (ns: NoteDTO[], fn: (ns: NoteDTO[]) => NoteDTO[]) => fn(ns));
  const [saving, startTransition] = React.useTransition();
  const view = React.useSyncExternalStore(subscribeView, readView, () => "grid" as View);

  const [tab, setTab] = React.useState<Tab>("all");
  const [q, setQ] = React.useState("");
  const [editor, setEditor] = React.useState<EditorState | null>(() =>
    initialNoteId && serverNotes.some((n) => n.id === initialNoteId) ? { key: 0, id: initialNoteId, defaults: {} } : null,
  );
  const [manageLabels, setManageLabels] = React.useState(false);
  const [confirmDelete, setConfirmDelete] = React.useState<NoteDTO | null>(null);
  const searchRef = React.useRef<HTMLInputElement>(null);
  const seq = React.useRef(1);

  const ctx = React.useMemo(() => ({ areas, wallets, categories, currency }), [areas, wallets, categories, currency]);
  const labelById = React.useMemo(() => new Map(labels.map((l) => [l.id, l])), [labels]);
  const activeTab: Tab = tab === "all" || tab === "archive" || labelById.has(tab) ? tab : "all";

  // Deep link (?note=<id>) to a note that doesn't exist.
  const missingNote = initialNoteId && !serverNotes.some((n) => n.id === initialNoteId);
  React.useEffect(() => {
    if (missingNote) push({ text: "Catatan tidak ditemukan", tone: "error" });
  }, [missingNote, push]);

  const openNote = React.useCallback((id: string | null, defaults: EditorState["defaults"] = {}) => {
    setEditor({ key: seq.current++, id, defaults });
  }, []);

  const closeEditor = React.useCallback(() => {
    setEditor(null);
    if (window.location.search.includes("note=")) window.history.replaceState(null, "", "/notes");
  }, []);

  const newNote = React.useCallback(() => {
    openNote(null, activeTab !== "all" && activeTab !== "archive" ? { labels: [activeTab] } : {});
  }, [activeTab, openNote]);

  // Shortcuts: n = new note, / = search.
  React.useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.metaKey || e.ctrlKey || e.altKey || isTypingTarget(e.target)) return;
      if (document.querySelector('[role="dialog"][aria-modal="true"]')) return;
      if (e.key === "n" || e.key === "N") {
        e.preventDefault();
        newNote();
      } else if (e.key === "/") {
        e.preventDefault();
        searchRef.current?.focus();
      }
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [newNote]);

  // Link titles are fetched by the server after a save — pull them once shortly after.
  const untitled = React.useMemo(
    () =>
      notes
        .filter((n) => n.links.some((l) => !l.title))
        .map((n) => `${n.id}@${n.updatedAt}`)
        .join(","),
    [notes],
  );
  const refreshed = React.useRef(new Set<string>());
  React.useEffect(() => {
    if (!untitled || refreshed.current.has(untitled)) return;
    const recent = notes.some((n) => n.links.some((l) => !l.title) && Date.now() - new Date(n.updatedAt).getTime() < 60_000);
    if (!recent) return;
    const t = setTimeout(() => {
      refreshed.current.add(untitled);
      router.refresh();
    }, 3500);
    return () => clearTimeout(t);
  }, [untitled, notes, router]);

  // ---------- Card actions (optimistic) ----------

  const mutate = React.useCallback(
    (id: string, patch: (n: NoteDTO) => NoteDTO, action: () => Promise<{ ok: boolean; error?: string }>, done?: () => void) => {
      startTransition(async () => {
        applyOptimistic((ns) => ns.map((n) => (n.id === id ? patch(n) : n)));
        const res = await action().catch(() => ({ ok: false, error: "Terjadi kesalahan, coba lagi" }));
        if (!res.ok) push({ text: res.error ?? "Gagal menyimpan", tone: "error" });
        else done?.();
      });
    },
    [applyOptimistic, push],
  );

  const actions: CardActions = React.useMemo(
    () => ({
      open: (id) => openNote(id),
      pin: (n) =>
        mutate(
          n.id,
          (x) => ({ ...x, pinned: !x.pinned }),
          () => setNotePinned(n.id, !n.pinned),
        ),
      archive: (n) =>
        mutate(
          n.id,
          (x) => ({ ...x, archived: !x.archived }),
          () => setNoteArchived(n.id, !n.archived),
          () =>
            push({
              text: n.archived ? "Catatan dikeluarkan dari arsip" : "Catatan diarsipkan",
              tone: "success",
              action: {
                label: "Urungkan",
                run: () =>
                  mutate(
                    n.id,
                    (x) => ({ ...x, archived: n.archived }),
                    () => setNoteArchived(n.id, n.archived),
                  ),
              },
            }),
        ),
      color: (n, c: NoteColorId | null) =>
        mutate(
          n.id,
          (x) => ({ ...x, color: c }),
          () => setNoteColor(n.id, c),
        ),
      toggleItem: (n, itemId) =>
        mutate(
          n.id,
          (x) => ({ ...x, checklist: x.checklist.map((i) => (i.id === itemId ? { ...i, done: !i.done } : i)) }),
          () => toggleChecklistItem(n.id, itemId),
        ),
      remove: (n) => setConfirmDelete(n),
      filterLabel: (id) => {
        setTab(id);
        window.scrollTo({ top: 0, behavior: "smooth" });
      },
    }),
    [mutate, openNote, push],
  );

  function doDelete(n: NoteDTO) {
    setConfirmDelete(null);
    startTransition(async () => {
      applyOptimistic((ns) => ns.filter((x) => x.id !== n.id));
      const res = await deleteNote(n.id).catch(() => ({ ok: false as const, error: "Gagal menghapus catatan" }));
      push(res.ok ? { text: "Catatan dihapus", tone: "success" } : { text: res.error, tone: "error" });
    });
  }

  function deleteFromEditor(id: string, after: Promise<unknown>) {
    startTransition(async () => {
      applyOptimistic((ns) => ns.filter((x) => x.id !== id));
      await after.catch(() => null);
      const res = await deleteNote(id).catch(() => ({ ok: false as const, error: "Gagal menghapus catatan" }));
      push(res.ok ? { text: "Catatan dihapus", tone: "success" } : { text: res.error, tone: "error" });
    });
  }

  // ---------- Filtering ----------

  const inTab = React.useMemo(() => {
    if (activeTab === "archive") return notes.filter((n) => n.archived);
    const live = notes.filter((n) => !n.archived);
    return activeTab === "all" ? live : live.filter((n) => n.labels.includes(activeTab));
  }, [notes, activeTab]);

  const query = q.trim();
  const shown = React.useMemo(() => {
    const list = query ? inTab.filter((n) => noteMatches(n, query)) : inTab;
    return [...list].sort(compareNotes);
  }, [inTab, query]);
  const archivedHits = React.useMemo(
    () => (query && activeTab !== "archive" ? notes.filter((n) => n.archived && noteMatches(n, query)).length : 0),
    [notes, query, activeTab],
  );

  const pinned = activeTab === "archive" ? [] : shown.filter((n) => n.pinned);
  const others = activeTab === "archive" ? shown : shown.filter((n) => !n.pinned);

  const tabLabels = labels.filter((l) => l.pinnedTab);
  const extraTab = activeTab !== "all" && activeTab !== "archive" && !labelById.get(activeTab)?.pinnedTab ? labelById.get(activeTab) : undefined;
  const liveCount = (id: string) => notes.filter((n) => !n.archived && n.labels.includes(id)).length;

  const editorNote = editor?.id ? notes.find((n) => n.id === editor.id) : undefined;
  const tabName = activeTab === "archive" ? "Arsip" : activeTab === "all" ? null : labelById.get(activeTab)?.name;

  return (
    <div className="min-w-0">
      <PageHeader
        title="Catatan"
        description="Tangkap ide cepat, lalu jadikan tugas, konten, atau transaksi."
        action={
          <div className="flex items-center gap-2">
            <SavingHint pending={saving} />
            <div className="flex rounded-lg border border-border bg-surface p-0.5" role="group" aria-label="Tampilan">
              <button
                type="button"
                onClick={() => writeView("grid")}
                aria-pressed={view === "grid"}
                aria-label="Tampilan grid"
                title="Grid"
                className={cn("rounded-md p-1.5", view === "grid" ? "bg-primary-soft text-primary" : "text-muted hover:text-foreground")}
              >
                <LayoutGrid className="h-4 w-4" />
              </button>
              <button
                type="button"
                onClick={() => writeView("list")}
                aria-pressed={view === "list"}
                aria-label="Tampilan daftar"
                title="Daftar"
                className={cn("rounded-md p-1.5", view === "list" ? "bg-primary-soft text-primary" : "text-muted hover:text-foreground")}
              >
                <Rows3 className="h-4 w-4" />
              </button>
            </div>
            <Button onClick={newNote} title="Catatan baru (N)">
              <Plus className="h-4 w-4" /> Catatan baru
            </Button>
          </div>
        }
      />

      {/* Search */}
      <div className="relative mb-3">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
        <input
          ref={searchRef}
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Escape") {
              setQ("");
              e.currentTarget.blur();
            }
          }}
          placeholder="Cari catatan, checklist, transkrip…  ( / )"
          aria-label="Cari catatan"
          className="h-10 w-full rounded-lg border border-border bg-surface pl-9 pr-9 text-sm text-foreground outline-none transition placeholder:text-muted-soft focus:border-primary focus:ring-2 focus:ring-primary/20 [&::-webkit-search-cancel-button]:hidden"
        />
        {q && (
          <button
            type="button"
            onClick={() => setQ("")}
            aria-label="Hapus pencarian"
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-muted hover:bg-accent hover:text-foreground"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>

      {/* Tabs */}
      <div className="-mx-4 mb-5 flex items-center gap-1.5 overflow-x-auto px-4 pb-1 sm:mx-0 sm:px-0" role="tablist" aria-label="Filter catatan">
        <TabButton active={activeTab === "all"} onClick={() => setTab("all")}>
          Semua
        </TabButton>
        {tabLabels.map((l) => (
          <TabButton key={l.id} active={activeTab === l.id} onClick={() => setTab(l.id)} color={l.color} count={liveCount(l.id)}>
            {l.name}
          </TabButton>
        ))}
        {extraTab && (
          <TabButton active color={extraTab.color} onClick={() => setTab(extraTab.id)}>
            {extraTab.name}
          </TabButton>
        )}
        <TabButton active={activeTab === "archive"} onClick={() => setTab("archive")}>
          <Archive className="h-3.5 w-3.5" /> Arsip
        </TabButton>
        <div className="flex-1" />
        <button
          type="button"
          onClick={() => setManageLabels(true)}
          className="flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-medium text-muted transition hover:bg-accent hover:text-foreground"
        >
          <Settings2 className="h-4 w-4" /> Kelola label
        </button>
      </div>

      {/* Notes */}
      {shown.length === 0 ? (
        <Empty
          query={query}
          tabName={tabName ?? null}
          archive={activeTab === "archive"}
          noNotes={notes.length === 0}
          archivedHits={archivedHits}
          onNew={newNote}
          onShowArchive={() => setTab("archive")}
        />
      ) : (
        <div className="space-y-6">
          {pinned.length > 0 && (
            <NoteSection title="Disematkan" notes={pinned} labels={labelById} actions={actions} view={view} />
          )}
          {others.length > 0 && (
            <NoteSection
              title={pinned.length > 0 ? "Lainnya" : null}
              notes={others}
              labels={labelById}
              actions={actions}
              view={view}
            />
          )}
          {archivedHits > 0 && (
            <p className="text-center text-sm text-muted">
              {archivedHits} catatan cocok di{" "}
              <button type="button" className="font-medium text-primary hover:underline" onClick={() => setTab("archive")}>
                Arsip
              </button>
            </p>
          )}
        </div>
      )}

      {editor && (
        <NoteEditor
          key={editor.key}
          noteId={editor.id}
          note={editorNote}
          defaults={editor.defaults}
          labels={labels}
          ctx={ctx}
          toast={push}
          onCreated={(id) => setEditor((e) => (e ? { ...e, id } : e))}
          onClose={closeEditor}
          onDelete={deleteFromEditor}
        />
      )}

      <LabelManager open={manageLabels} onClose={() => setManageLabels(false)} labels={labels} notes={notes} toast={push} />

      <Modal open={!!confirmDelete} onClose={() => setConfirmDelete(null)} title="Hapus catatan?">
        <p className="text-sm text-muted">
          &ldquo;{confirmDelete?.title || "Catatan tanpa judul"}&rdquo; beserta foto dan rekamannya dihapus permanen. Arsipkan saja kalau
          hanya ingin menyembunyikannya.
        </p>
        <div className="mt-5 flex flex-wrap justify-end gap-2">
          <Button variant="ghost" onClick={() => setConfirmDelete(null)}>
            Batal
          </Button>
          {confirmDelete && !confirmDelete.archived && (
            <Button
              variant="outline"
              onClick={() => {
                const n = confirmDelete;
                setConfirmDelete(null);
                actions.archive(n);
              }}
            >
              Arsipkan
            </Button>
          )}
          <Button variant="danger" onClick={() => confirmDelete && doDelete(confirmDelete)}>
            Hapus
          </Button>
        </div>
      </Modal>

      <Toasts toasts={toasts} dismiss={dismiss} />
    </div>
  );
}

function TabButton({
  active,
  onClick,
  color,
  count,
  children,
}: {
  active: boolean;
  onClick: () => void;
  color?: string;
  count?: number;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={cn(
        "flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border px-3 py-1.5 text-sm font-medium transition",
        active ? "border-primary bg-primary-soft text-primary" : "border-border bg-surface text-muted hover:bg-accent hover:text-foreground",
      )}
    >
      {color && <span className="h-2 w-2 rounded-full" style={{ background: color }} />}
      {children}
      {count !== undefined && count > 0 && <span className="text-xs opacity-70">{count}</span>}
    </button>
  );
}

function NoteSection({
  title,
  notes,
  labels,
  actions,
  view,
}: {
  title: string | null;
  notes: NoteDTO[];
  labels: Map<string, NoteLabelDTO>;
  actions: CardActions;
  view: View;
}) {
  return (
    <section aria-label={title ?? "Catatan"}>
      {title && <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">{title}</h2>}
      <div className={view === "list" ? "mx-auto max-w-2xl" : "columns-1 gap-4 sm:columns-2 lg:columns-3 xl:columns-4"}>
        {notes.map((n) => (
          <NoteCard key={n.id} note={n} labels={labels} actions={actions} list={view === "list"} />
        ))}
      </div>
    </section>
  );
}

function Empty({
  query,
  tabName,
  archive,
  noNotes,
  archivedHits,
  onNew,
  onShowArchive,
}: {
  query: string;
  tabName: string | null;
  archive: boolean;
  noNotes: boolean;
  archivedHits: number;
  onNew: () => void;
  onShowArchive: () => void;
}) {
  if (query)
    return (
      <EmptyState
        icon={Search}
        title="Tidak ada yang cocok"
        description={`Tidak ada catatan${tabName ? ` di ${tabName}` : ""} yang cocok dengan “${query}”.`}
        action={
          archivedHits > 0 ? (
            <Button variant="outline" onClick={onShowArchive}>
              Lihat {archivedHits} hasil di Arsip
            </Button>
          ) : undefined
        }
      />
    );
  if (archive) return <EmptyState icon={Archive} title="Arsip kosong" description="Catatan yang diarsipkan muncul di sini." />;
  if (tabName)
    return (
      <EmptyState
        icon={Tag}
        title={`Belum ada catatan “${tabName}”`}
        description="Catatan baru dari tab ini otomatis diberi label ini."
        action={
          <Button onClick={onNew}>
            <Plus className="h-4 w-4" /> Catatan baru
          </Button>
        }
      />
    );
  return (
    <EmptyState
      icon={StickyNote}
      title={noNotes ? "Belum ada catatan" : "Semua catatan diarsipkan"}
      description="Tulis ide, daftar belanja, atau rekaman suara — lalu jadikan tugas, konten, atau transaksi. Tekan N untuk catatan baru."
      action={
        <Button onClick={onNew}>
          <Plus className="h-4 w-4" /> Catatan baru
        </Button>
      }
    />
  );
}
