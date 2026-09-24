import * as React from "react";
import { isHttpUrl } from "@/lib/notes";

/**
 * Tiny, safe markdown renderer for ideas / scripts: builds React elements only (no
 * dangerouslySetInnerHTML), so any HTML in the text shows as plain text. Supports
 * headings (#–###), bullet / numbered / task lists, blockquotes, fenced code, horizontal
 * rules, **bold**, *italic*, `code`, ~~strike~~ and [links](https://…) / bare URLs
 * (http(s) only, opened in a new tab).
 */
export function Markdown({ text, className }: { text: string; className?: string }) {
  const blocks = React.useMemo(() => parseBlocks(text), [text]);
  return <div className={className}>{blocks}</div>;
}

type ListKind = "ul" | "ol";

function parseBlocks(text: string): React.ReactNode[] {
  const lines = text.replace(/\r\n?/g, "\n").split("\n");
  const out: React.ReactNode[] = [];
  let i = 0;
  let key = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*```/.test(line)) {
      const code: string[] = [];
      i++;
      while (i < lines.length && !/^\s*```/.test(lines[i])) code.push(lines[i++]);
      i++;
      out.push(
        <pre key={key++} className="my-2 overflow-x-auto rounded-lg bg-accent p-3 text-xs">
          <code>{code.join("\n")}</code>
        </pre>,
      );
      continue;
    }
    const h = /^(#{1,3})\s+(.*)$/.exec(line);
    if (h) {
      const cls = h[1].length === 1 ? "text-lg font-bold" : h[1].length === 2 ? "text-base font-bold" : "text-sm font-semibold";
      out.push(
        <p key={key++} className={`mt-3 mb-1 first:mt-0 ${cls}`}>
          {inline(h[2])}
        </p>,
      );
      i++;
      continue;
    }
    if (/^\s*([-*_])\s*\1\s*\1[\s\-*_]*$/.test(line)) {
      out.push(<hr key={key++} className="my-3 border-border" />);
      i++;
      continue;
    }
    if (/^\s*>/.test(line)) {
      const q: string[] = [];
      while (i < lines.length && /^\s*>/.test(lines[i])) q.push(lines[i++].replace(/^\s*>\s?/, ""));
      out.push(
        <blockquote key={key++} className="my-2 border-l-4 border-border pl-3 text-muted">
          {q.map((l, j) => (
            <React.Fragment key={j}>
              {j > 0 && <br />}
              {inline(l)}
            </React.Fragment>
          ))}
        </blockquote>,
      );
      continue;
    }
    const li = listItem(line);
    if (li) {
      const kind = li.kind;
      const items: ReturnType<typeof listItem>[] = [];
      while (i < lines.length) {
        const x = listItem(lines[i]);
        if (!x || x.kind !== kind) break;
        items.push(x);
        i++;
      }
      const Tag = kind;
      out.push(
        <Tag key={key++} className={`my-1 space-y-0.5 pl-5 ${kind === "ul" ? "list-disc" : "list-decimal"}`}>
          {items.map((it, j) =>
            it!.task != null ? (
              <li key={j} className="list-none -ml-5 flex items-start gap-2">
                <input type="checkbox" checked={it!.task} readOnly disabled className="mt-1" aria-label={it!.task ? "Selesai" : "Belum"} />
                <span className={it!.task ? "text-muted line-through" : undefined}>{inline(it!.text)}</span>
              </li>
            ) : (
              <li key={j}>{inline(it!.text)}</li>
            ),
          )}
        </Tag>,
      );
      continue;
    }
    if (!line.trim()) {
      i++;
      continue;
    }
    const para: string[] = [];
    while (i < lines.length && lines[i].trim() && !isBlockStart(lines[i])) para.push(lines[i++]);
    out.push(
      <p key={key++} className="my-1.5 first:mt-0">
        {para.map((l, j) => (
          <React.Fragment key={j}>
            {j > 0 && <br />}
            {inline(l)}
          </React.Fragment>
        ))}
      </p>,
    );
  }
  return out;
}

function isBlockStart(line: string) {
  return /^\s*```/.test(line) || /^#{1,3}\s/.test(line) || /^\s*>/.test(line) || !!listItem(line);
}

function listItem(line: string): { kind: ListKind; text: string; task: boolean | null } | null {
  const ul = /^\s*[-*+]\s+(.*)$/.exec(line);
  if (ul) {
    const t = /^\[( |x|X)\]\s+(.*)$/.exec(ul[1]);
    return t ? { kind: "ul", text: t[2], task: t[1] !== " " } : { kind: "ul", text: ul[1], task: null };
  }
  const ol = /^\s*\d+[.)]\s+(.*)$/.exec(line);
  return ol ? { kind: "ol", text: ol[1], task: null } : null;
}

const INLINE_RE = /(`[^`]+`)|(\*\*[^*]+\*\*|__[^_]+__)|(~~[^~]+~~)|(\*[^*\s][^*]*\*|_[^_\s][^_]*_)|(\[[^\]]+\]\([^)\s]+\))|(https?:\/\/[^\s<>()]+[^\s<>().,!?;:'"])/g;

function inline(text: string, depth = 0): React.ReactNode[] {
  const out: React.ReactNode[] = [];
  let last = 0;
  let k = 0;
  for (const m of text.matchAll(INLINE_RE)) {
    const idx = m.index ?? 0;
    if (idx > last) out.push(text.slice(last, idx));
    const s = m[0];
    const nest = (inner: string) => (depth < 4 ? inline(inner, depth + 1) : inner);
    if (m[1]) out.push(<code key={k++} className="rounded bg-accent px-1 text-[0.9em]">{s.slice(1, -1)}</code>);
    else if (m[2]) out.push(<strong key={k++}>{nest(s.slice(2, -2))}</strong>);
    else if (m[3]) out.push(<s key={k++}>{nest(s.slice(2, -2))}</s>);
    else if (m[4]) out.push(<em key={k++}>{nest(s.slice(1, -1))}</em>);
    else if (m[5]) {
      const lm = /^\[([^\]]+)\]\(([^)\s]+)\)$/.exec(s)!;
      out.push(isHttpUrl(lm[2]) ? <ExtLink key={k++} href={lm[2]}>{nest(lm[1])}</ExtLink> : s);
    } else if (m[6]) out.push(isHttpUrl(s) ? <ExtLink key={k++} href={s}>{s}</ExtLink> : s);
    last = idx + s.length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

function ExtLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer nofollow" className="break-all text-primary underline-offset-2 hover:underline">
      {children}
    </a>
  );
}
