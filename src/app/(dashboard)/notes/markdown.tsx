import * as React from "react";
import { isHttpUrl } from "@/lib/notes";
import { cn } from "@/lib/utils";

/**
 * Tiny, safe renderer for the notes Markdown subset (docs/notes.md "Body format"):
 * headings, bold, italic, strikethrough, inline code, fenced code, links (+ bare URLs),
 * bullet / numbered lists, quotes and rules. It builds React elements directly — raw HTML
 * in the text is shown as text, never injected — and only http(s)/mailto links are
 * clickable (opened in a new tab with rel="noopener noreferrer").
 */

const INLINE_RE =
  /(`+)([^`\n]+?)\1|\[([^\]\n]+)\]\(([^)\s]+)\)|(https?:\/\/[^\s<>"'`]+)|\*\*(?=\S)(.+?)\*\*|__(?=\S)(.+?)__|~~(?=\S)(.+?)~~|\*(?=[^\s*])([^*\n]*?[^\s*])\*|(?<![\p{L}\p{N}])_(?=[^\s_])([^_\n]*?[^\s_])_(?![\p{L}\p{N}])/gu;

function safeHref(url: string): string | null {
  if (isHttpUrl(url)) return url;
  if (/^mailto:[^\s@]+@[^\s@]+$/i.test(url)) return url;
  return null;
}

/** Trailing punctuation / unbalanced brackets are not part of a bare URL. */
function trimUrl(url: string): string {
  const count = (s: string, ch: string) => s.split(ch).length - 1;
  let u = url;
  for (;;) {
    const last = u.at(-1)!;
    if (".,;:!?'\"*_~".includes(last)) u = u.slice(0, -1);
    else if (last === ")" && count(u, "(") < count(u, ")")) u = u.slice(0, -1);
    else if (last === "]" && count(u, "[") < count(u, "]")) u = u.slice(0, -1);
    else return u;
  }
}

function A({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      onClick={(e) => e.stopPropagation()}
      className="break-words text-primary underline underline-offset-2 hover:text-primary-hover"
    >
      {children}
    </a>
  );
}

/** `inLink`: inside a link's text — no nested links (`<a>` in `<a>` breaks hydration). */
export function renderInline(text: string, key = "i", inLink = false): React.ReactNode[] {
  const out: React.ReactNode[] = [];
  let last = 0;
  let n = 0;
  for (const m of text.matchAll(INLINE_RE)) {
    const start = m.index!;
    if (start > last) out.push(text.slice(last, start));
    const k = `${key}-${n++}`;
    let consumed = m[0].length;
    if (m[2] !== undefined) {
      out.push(
        <code key={k} className="rounded bg-black/[0.06] px-1 py-0.5 font-mono text-[0.9em]">
          {m[2]}
        </code>,
      );
    } else if (m[3] !== undefined) {
      const href = inLink ? null : safeHref(m[4]);
      out.push(
        href ? (
          <A key={k} href={href}>
            {renderInline(m[3], k, true)}
          </A>
        ) : (
          <React.Fragment key={k}>{m[0]}</React.Fragment>
        ),
      );
    } else if (m[5] !== undefined) {
      const url = trimUrl(m[5]);
      consumed = url.length;
      const href = inLink ? null : safeHref(url);
      out.push(href ? <A key={k} href={href}>{url}</A> : url);
    } else if (m[6] !== undefined || m[7] !== undefined) {
      out.push(<strong key={k}>{renderInline(m[6] ?? m[7], k, inLink)}</strong>);
    } else if (m[8] !== undefined) {
      out.push(<del key={k}>{renderInline(m[8], k, inLink)}</del>);
    } else {
      out.push(<em key={k}>{renderInline(m[9] ?? m[10], k, inLink)}</em>);
    }
    last = start + consumed;
    // A trimmed bare URL: the regex must continue right after the part we used.
    if (consumed !== m[0].length) {
      out.push(...renderInline(text.slice(last), `${k}r`, inLink));
      return out;
    }
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

function withBreaks(lines: string[], key: string): React.ReactNode[] {
  return lines.flatMap((l, i) => [i > 0 ? <br key={`${key}-br${i}`} /> : null, ...renderInline(l, `${key}-${i}`)]);
}

const HEADING_RE = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/;
const QUOTE_RE = /^\s{0,3}>\s?(.*)$/;
const BULLET_RE = /^\s*[-*+]\s+(.*)$/;
const NUMBER_RE = /^\s*(\d{1,9})[.)]\s+(.*)$/;
const HR_RE = /^\s{0,3}([-*_])(\s*\1){2,}\s*$/;
const FENCE_RE = /^\s{0,3}```/;

const isBlockStart = (l: string) =>
  HEADING_RE.test(l) || QUOTE_RE.test(l) || BULLET_RE.test(l) || NUMBER_RE.test(l) || HR_RE.test(l) || FENCE_RE.test(l);

function listItem(text: string, key: string) {
  const task = /^\[( |x|X)\]\s+(.*)$/.exec(text);
  if (!task) return <li key={key}>{renderInline(text, key)}</li>;
  const done = task[1] !== " ";
  return (
    <li key={key} className="list-none">
      <span aria-hidden className="-ml-4 mr-1 inline-block w-3">
        {done ? "☑" : "☐"}
      </span>
      <span className={cn(done && "text-muted line-through")}>{renderInline(task[2], key)}</span>
    </li>
  );
}

export function renderBlocks(body: string): React.ReactNode[] {
  const lines = body.replace(/\r\n?/g, "\n").split("\n");
  const out: React.ReactNode[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const key = `b${i}`;
    if (!line.trim()) {
      i++;
      continue;
    }
    if (FENCE_RE.test(line)) {
      const code: string[] = [];
      i++;
      while (i < lines.length && !FENCE_RE.test(lines[i])) code.push(lines[i++]);
      i++; // closing fence
      out.push(
        <pre key={key} className="overflow-x-auto rounded-lg bg-black/[0.06] p-3 font-mono text-xs">
          <code>{code.join("\n")}</code>
        </pre>,
      );
      continue;
    }
    const h = HEADING_RE.exec(line);
    if (h) {
      const level = h[1].length;
      const cls = level === 1 ? "text-lg font-bold" : level === 2 ? "text-base font-bold" : "text-sm font-semibold";
      const content = renderInline(h[2], key);
      out.push(
        level === 1 ? (
          <h3 key={key} className={cls}>{content}</h3>
        ) : level === 2 ? (
          <h4 key={key} className={cls}>{content}</h4>
        ) : (
          <h5 key={key} className={cls}>{content}</h5>
        ),
      );
      i++;
      continue;
    }
    if (HR_RE.test(line)) {
      out.push(<hr key={key} className="border-black/10" />);
      i++;
      continue;
    }
    if (QUOTE_RE.test(line)) {
      const q: string[] = [];
      while (i < lines.length && QUOTE_RE.test(lines[i])) q.push(QUOTE_RE.exec(lines[i++])![1]);
      out.push(
        <blockquote key={key} className="border-l-4 border-black/15 pl-3 text-muted">
          {withBreaks(q, key)}
        </blockquote>,
      );
      continue;
    }
    if (BULLET_RE.test(line)) {
      const items: React.ReactNode[] = [];
      while (i < lines.length && BULLET_RE.test(lines[i])) items.push(listItem(BULLET_RE.exec(lines[i])![1], `${key}-${i++}`));
      out.push(
        <ul key={key} className="list-disc space-y-0.5 pl-5">
          {items}
        </ul>,
      );
      continue;
    }
    if (NUMBER_RE.test(line)) {
      const start = Number(NUMBER_RE.exec(line)![1]);
      const items: React.ReactNode[] = [];
      while (i < lines.length && NUMBER_RE.test(lines[i])) {
        const m = NUMBER_RE.exec(lines[i])!;
        items.push(<li key={`${key}-${i}`}>{renderInline(m[2], `${key}-${i}`)}</li>);
        i++;
      }
      out.push(
        <ol key={key} start={start} className="list-decimal space-y-0.5 pl-5">
          {items}
        </ol>,
      );
      continue;
    }
    const para: string[] = [];
    while (i < lines.length && lines[i].trim() && (para.length === 0 || !isBlockStart(lines[i]))) para.push(lines[i++]);
    out.push(<p key={key}>{withBreaks(para, key)}</p>);
  }
  return out;
}

export function Markdown({ text, className }: { text: string; className?: string }) {
  const blocks = React.useMemo(() => renderBlocks(text), [text]);
  return <div className={cn("space-y-2 break-words text-sm leading-relaxed", className)}>{blocks}</div>;
}
