"use client";

import * as React from "react";
import Link from "next/link";
import { CheckSquare, Image as ImageIcon, Inbox, Lightbulb, Mic } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { EmptyState } from "@/components/ui/misc";
import { CONTENT_TITLE_MAX, FORMATS, type FormatId } from "@/lib/content";
import { stripMarkdown } from "@/lib/notes";
import { convertNoteToContent } from "../notes/actions";
import { usePlanner } from "./planner";
import { formatDateTime, useToast } from "./ui";
import type { NoteDTO } from "./types";
import { LinkPendingIcon } from "@/components/link-pending";

const noteTitle = (n: NoteDTO) =>
  (n.title ?? "").trim() ||
  stripMarkdown(n.body.split("\n").find((l) => l.trim()) ?? "").slice(0, CONTENT_TITLE_MAX) ||
  n.checklist[0]?.text ||
  "Ide tanpa judul";

/** Notes labelled "Ide Konten" that haven't become content yet. */
export function IdeaInbox() {
  const { data, tz } = usePlanner();
  const [converting, setConverting] = React.useState<NoteDTO | null>(null);
  const [hidden, setHidden] = React.useState<Set<string>>(() => new Set());
  const list = data.inbox.filter((n) => !hidden.has(n.id));

  if (list.length === 0) {
    return (
      <EmptyState
        icon={Inbox}
        title="Belum ada ide masuk"
        description="Beri label “Ide Konten” pada catatan (di web atau aplikasi) — catatan itu muncul di sini dan bisa dijadikan konten dengan sekali klik."
        action={
          <Link href="/notes">
            <Button variant="outline">
              <LinkPendingIcon>
                <Lightbulb className="h-4 w-4" />
              </LinkPendingIcon>{" "}
              Buka Catatan
            </Button>
          </Link>
        }
      />
    );
  }

  return (
    <>
      <p className="mb-3 text-sm text-muted">{list.length} catatan berlabel “Ide Konten” menunggu dijadikan konten.</p>
      <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {list.map((n) => {
          const excerpt = stripMarkdown(n.body.replace(/\n+/g, " ")).slice(0, 220);
          return (
            <li key={n.id} className="flex flex-col rounded-card border border-border bg-card p-4 shadow-sm">
              <p className="line-clamp-2 break-words font-semibold text-foreground">{noteTitle(n)}</p>
              {excerpt && <p className="mt-1 line-clamp-4 break-words text-sm text-muted">{excerpt}</p>}
              <div className="mt-2 flex flex-wrap items-center gap-3 text-xs text-muted-soft">
                <span>{formatDateTime(n.updatedAt, tz, { weekday: false })}</span>
                {n.checklist.length > 0 && (
                  <span className="inline-flex items-center gap-0.5">
                    <CheckSquare className="h-3 w-3" /> {n.checklist.length}
                  </span>
                )}
                {n.photos.length > 0 && (
                  <span className="inline-flex items-center gap-0.5">
                    <ImageIcon className="h-3 w-3" /> {n.photos.length}
                  </span>
                )}
                {n.audio.length > 0 && (
                  <span className="inline-flex items-center gap-0.5">
                    <Mic className="h-3 w-3" /> {n.audio.length}
                  </span>
                )}
              </div>
              <div className="mt-auto pt-3">
                <Button size="sm" onClick={() => setConverting(n)}>
                  <Lightbulb className="h-4 w-4" /> Jadikan konten
                </Button>
              </div>
            </li>
          );
        })}
      </ul>
      {converting && (
        <ConvertDialog
          note={converting}
          onClose={() => setConverting(null)}
          onDone={(id) => setHidden((s) => new Set(s).add(id))}
        />
      )}
    </>
  );
}

function ConvertDialog({ note, onClose, onDone }: { note: NoteDTO; onClose: () => void; onDone: (noteId: string) => void }) {
  const { data, mutate, openItem } = usePlanner();
  const toast = useToast();
  const [title, setTitle] = React.useState(noteTitle(note).slice(0, CONTENT_TITLE_MAX));
  const [format, setFormat] = React.useState("");
  const [pillar, setPillar] = React.useState("");
  const [busy, setBusy] = React.useState(false);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    setBusy(true);
    mutate(
      null,
      async () => {
        try {
          return await convertNoteToContent(note.id, { title: title.trim(), format: (format || null) as FormatId | null, pillar: pillar || null });
        } finally {
          setBusy(false);
        }
      },
      (r) => {
        onDone(note.id);
        onClose();
        toast({ text: "Ide jadi konten di kolom Ide ✓", tone: "success", action: { label: "Buka", run: () => openItem({ mode: "edit", id: r.contentId }) } });
      },
    );
  }

  return (
    <Modal open onClose={onClose} title="Jadikan konten" description="Isi catatan (teks, checklist, foto) disalin ke konten baru di tahap Ide.">
      <form onSubmit={submit} className="space-y-3">
        <Field label="Judul">
          <Input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={CONTENT_TITLE_MAX} required autoFocus />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Format">
            <Select value={format} onChange={(e) => setFormat(e.target.value)}>
              <option value="">—</option>
              {FORMATS.map((f) => (
                <option key={f.id} value={f.id}>
                  {f.label}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Pilar">
            <Select value={pillar} onChange={(e) => setPillar(e.target.value)}>
              <option value="">—</option>
              {data.pillars.map((p) => (
                <option key={p.id} value={p.name}>
                  {p.name}
                </option>
              ))}
            </Select>
          </Field>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="ghost" onClick={onClose}>
            Batal
          </Button>
          <Button type="submit" loading={busy} disabled={!title.trim()}>
            {busy ? "Menyimpan…" : "Jadikan konten"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
