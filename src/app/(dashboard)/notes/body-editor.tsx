"use client";

import * as React from "react";
import { Bold, Code, Eye, Heading, Italic, Link2, List, ListOrdered, Pencil, Quote } from "lucide-react";
import { NOTE_BODY_MAX } from "@/lib/notes";
import { cn } from "@/lib/utils";
import { Markdown } from "./markdown";

type ToolId = "bold" | "italic" | "heading" | "bullet" | "number" | "quote" | "link" | "code";

const TOOLS: { id: ToolId; label: string; icon: React.ComponentType<{ className?: string }>; kbd?: string }[] = [
  { id: "bold", label: "Tebal", icon: Bold, kbd: "Ctrl+B" },
  { id: "italic", label: "Miring", icon: Italic, kbd: "Ctrl+I" },
  { id: "heading", label: "Judul", icon: Heading },
  { id: "bullet", label: "Daftar poin", icon: List },
  { id: "number", label: "Daftar bernomor", icon: ListOrdered },
  { id: "quote", label: "Kutipan", icon: Quote },
  { id: "link", label: "Tautan", icon: Link2, kbd: "Ctrl+K" },
  { id: "code", label: "Kode", icon: Code },
];

/**
 * Plain-text Markdown editor with a small formatting toolbar and a preview toggle.
 * Edits go through `insertText` when the browser supports it, so undo (Ctrl+Z) keeps
 * working after toolbar actions.
 */
export function BodyEditor({
  value,
  onChange,
  autoFocus,
}: {
  value: string;
  onChange: (v: string) => void;
  autoFocus?: boolean;
}) {
  const ref = React.useRef<HTMLTextAreaElement>(null);
  const [preview, setPreview] = React.useState(false);

  const pendingSel = React.useRef<[number, number] | null>(null);

  // Grow with the content (bounded by CSS max-height); restore a pending selection.
  React.useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (pendingSel.current) {
      el.setSelectionRange(...pendingSel.current);
      pendingSel.current = null;
    }
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight + 2}px`;
  }, [value, preview]);

  /** Replace [start, end) with `text` and select [selStart, selEnd) (absolute, after the edit). */
  function replace(start: number, end: number, text: string, selStart: number, selEnd: number) {
    const el = ref.current;
    if (!el) return;
    el.focus();
    el.setSelectionRange(start, end);
    let ok = false;
    try {
      ok = document.execCommand("insertText", false, text);
    } catch {
      ok = false;
    }
    if (ok && el.value === value.slice(0, start) + text + value.slice(end)) {
      // The browser already updated the textarea (and undo stack); onChange ran via input.
      el.setSelectionRange(selStart, selEnd);
    } else {
      pendingSel.current = [selStart, selEnd];
      onChange(value.slice(0, start) + text + value.slice(end));
    }
  }

  function wrap(before: string, after: string, placeholder: string) {
    const el = ref.current;
    if (!el) return;
    const s = el.selectionStart;
    const e = el.selectionEnd;
    const sel = value.slice(s, e);
    // Toggle off when the selection is already wrapped.
    if (sel && value.slice(s - before.length, s) === before && value.slice(e, e + after.length) === after) {
      replace(s - before.length, e + after.length, sel, s - before.length, e - before.length);
      return;
    }
    const inner = sel || placeholder;
    replace(s, e, before + inner + after, s + before.length, s + before.length + inner.length);
  }

  function prefixLines(kind: "heading" | "bullet" | "number" | "quote") {
    const el = ref.current;
    if (!el) return;
    const s = el.selectionStart;
    const e = el.selectionEnd;
    const lineStart = value.lastIndexOf("\n", s - 1) + 1;
    const nl = value.indexOf("\n", e);
    const lineEnd = nl === -1 ? value.length : nl;
    const lines = value.slice(lineStart, lineEnd).split("\n");
    const re = { heading: /^#{1,6}\s+/, bullet: /^\s*[-*+]\s+/, number: /^\s*\d+[.)]\s+/, quote: /^>\s?/ }[kind];
    const all = lines.every((l) => re.test(l) || !l.trim());
    const next = lines.map((l, i) => {
      if (all) return l.replace(re, "");
      const bare = l.replace(/^(#{1,6}\s+|\s*[-*+]\s+|\s*\d+[.)]\s+|>\s?)/, "");
      if (!bare.trim() && lines.length > 1) return l;
      const p = kind === "heading" ? "## " : kind === "bullet" ? "- " : kind === "number" ? `${i + 1}. ` : "> ";
      return p + bare;
    });
    const text = next.join("\n");
    replace(lineStart, lineEnd, text, lineStart + text.length, lineStart + text.length);
  }

  function link() {
    const el = ref.current;
    if (!el) return;
    const s = el.selectionStart;
    const e = el.selectionEnd;
    const sel = value.slice(s, e);
    if (/^https?:\/\/\S+$/.test(sel)) {
      const text = `[teks](${sel})`;
      replace(s, e, text, s + 1, s + 5);
      return;
    }
    const label = sel || "teks";
    const text = `[${label}](https://)`;
    const urlStart = s + label.length + 3;
    replace(s, e, text, urlStart, urlStart + "https://".length);
  }

  function runTool(id: ToolId) {
    if (id === "bold") wrap("**", "**", "tebal");
    else if (id === "italic") wrap("_", "_", "miring");
    else if (id === "code") wrap("`", "`", "kode");
    else if (id === "link") link();
    else prefixLines(id);
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    const mod = e.metaKey || e.ctrlKey;
    if (mod && !e.shiftKey && !e.altKey) {
      const k = e.key.toLowerCase();
      const tool = ({ b: "bold", i: "italic", k: "link" } as const)[k as "b" | "i" | "k"];
      if (tool) {
        e.preventDefault();
        runTool(tool);
        return;
      }
    }
    // Continue a list on Enter.
    if (e.key === "Enter" && !e.shiftKey && !mod) {
      const el = e.currentTarget;
      if (el.selectionStart !== el.selectionEnd) return;
      const pos = el.selectionStart;
      const lineStart = value.lastIndexOf("\n", pos - 1) + 1;
      const line = value.slice(lineStart, pos);
      const m = /^(\s*)([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?(.*)$/.exec(line);
      if (!m) return;
      e.preventDefault();
      if (!m[4].trim()) {
        // Empty item: end the list.
        replace(lineStart, pos, "", lineStart, lineStart);
        return;
      }
      const marker = /\d/.test(m[2]) ? `${parseInt(m[2], 10) + 1}${m[2].slice(-1)}` : m[2];
      const ins = `\n${m[1]}${marker} ${m[3] ? "[ ] " : ""}`;
      replace(pos, pos, ins, pos + ins.length, pos + ins.length);
    }
  }

  return (
    <div className="rounded-lg border border-black/10 bg-white/50 focus-within:border-primary focus-within:ring-2 focus-within:ring-primary/20">
      <div className="flex items-center gap-0.5 overflow-x-auto border-b border-black/10 px-1 py-1" role="toolbar" aria-label="Format teks">
        {TOOLS.map((t) => (
          <button
            key={t.label}
            type="button"
            title={t.kbd ? `${t.label} (${t.kbd})` : t.label}
            aria-label={t.label}
            disabled={preview}
            onMouseDown={(e) => e.preventDefault()}
            onClick={() => runTool(t.id)}
            className="shrink-0 rounded-md p-1.5 text-muted transition hover:bg-black/5 hover:text-foreground disabled:opacity-40"
          >
            <t.icon className="h-4 w-4" />
          </button>
        ))}
        <div className="flex-1" />
        <button
          type="button"
          onClick={() => setPreview((p) => !p)}
          aria-pressed={preview}
          className={cn(
            "flex shrink-0 items-center gap-1 rounded-md px-2 py-1 text-xs font-medium transition",
            preview ? "bg-primary-soft text-primary" : "text-muted hover:bg-black/5 hover:text-foreground",
          )}
        >
          {preview ? <Pencil className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
          {preview ? "Edit" : "Pratinjau"}
        </button>
      </div>
      {preview ? (
        <div className="min-h-32 px-3 py-2">
          {value.trim() ? <Markdown text={value} /> : <p className="text-sm text-muted-soft">Belum ada isi.</p>}
        </div>
      ) : (
        <textarea
          ref={ref}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={onKeyDown}
          autoFocus={autoFocus}
          maxLength={NOTE_BODY_MAX}
          placeholder="Tulis catatan… (Markdown: **tebal**, _miring_, - daftar, [tautan](https://…))"
          aria-label="Isi catatan"
          className="block max-h-[50vh] min-h-32 w-full resize-none bg-transparent px-3 py-2 text-sm leading-relaxed text-foreground outline-none placeholder:text-muted-soft"
        />
      )}
    </div>
  );
}
