import type { Metadata } from "next";
import Link from "next/link";
import { AlertTriangle, ChevronRight, File, Folder, FolderOpen } from "lucide-react";
import { Card } from "@/components/ui/card";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { LinkPending } from "@/components/link-pending";
import { cleanKillaPath, KillaError, killaEngine, requireKillaUser, type KillaFile, type KillaFileEntry } from "@/lib/killa";
import { Markdown } from "../../notes/markdown";
import { KillaNav } from "../killa-nav";
import { FileEditor } from "./file-editor";

export const metadata: Metadata = { title: "Berkas Killa — Ghina" };

type Search = { path?: string | string[]; file?: string | string[] };

const one = (v: string | string[] | undefined) => (typeof v === "string" ? v : "");
const href = (key: "path" | "file", p: string) => (p ? `/killa/files?${key}=${encodeURIComponent(p)}` : "/killa/files");
const join = (dir: string, name: string) => (dir ? `${dir.replace(/\/+$/, "")}/${name}` : name);
const parentOf = (p: string) => p.split("/").slice(0, -1).join("/");

function formatSize(n: number) {
  if (!Number.isFinite(n)) return "";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

async function attempt<T>(fn: () => Promise<T>): Promise<{ data: T; error: null } | { data: null; error: string }> {
  try {
    return { data: await fn(), error: null };
  } catch (e) {
    if (e instanceof KillaError) return { data: null, error: e.message };
    throw e;
  }
}

/** Browser of Killa's workspace: `?path=dir` lists a directory, `?file=path` shows (and edits) a text file. */
export default async function KillaFilesPage({ searchParams }: { searchParams: Promise<Search> }) {
  await requireKillaUser();
  const sp = await searchParams;
  let file: string;
  let dir: string;
  try {
    file = cleanKillaPath(one(sp.file));
    dir = file ? parentOf(file) : cleanKillaPath(one(sp.path));
  } catch {
    file = "";
    dir = "";
  }

  const result = file
    ? { kind: "file" as const, ...(await attempt(() => killaEngine.file(file))) }
    : { kind: "dir" as const, ...(await attempt(() => killaEngine.files(dir))) };

  return (
    <div>
      <PageHeader title="Killa" description="Isi workspace Killa." />
      <KillaNav />
      <Breadcrumbs path={file || dir} />
      {result.error ? (
        <div role="alert" className="flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{result.error}</span>
        </div>
      ) : result.kind === "file" ? (
        <FileView file={result.data as KillaFile} />
      ) : (
        <DirList dir={dir} entries={result.data as KillaFileEntry[]} />
      )}
    </div>
  );
}

function Breadcrumbs({ path }: { path: string }) {
  const parts = path ? path.split("/").filter(Boolean) : [];
  return (
    <nav aria-label="Lokasi" className="mb-3 flex flex-wrap items-center gap-1 text-sm">
      <Link href="/killa/files" className="inline-flex items-center gap-1 font-medium text-muted hover:text-foreground">
        workspace
        <LinkPending spinner={false} />
      </Link>
      {parts.map((part, i) => {
        const p = parts.slice(0, i + 1).join("/");
        const last = i === parts.length - 1;
        return (
          <span key={p} className="inline-flex items-center gap-1">
            <ChevronRight className="h-3.5 w-3.5 text-muted-soft" />
            {last ? (
              <span className="font-medium text-foreground">{part}</span>
            ) : (
              <Link href={href("path", p)} className="font-medium text-muted hover:text-foreground">
                {part}
                <LinkPending spinner={false} />
              </Link>
            )}
          </span>
        );
      })}
    </nav>
  );
}

function DirList({ dir, entries }: { dir: string; entries: KillaFileEntry[] }) {
  const sorted = [...entries].sort((a, b) =>
    a.type === b.type ? a.name.localeCompare(b.name) : a.type === "dir" ? -1 : 1,
  );
  if (!sorted.length) return <EmptyState icon={FolderOpen} title="Folder kosong" />;
  return (
    <Card className="divide-y divide-border-soft overflow-hidden">
      {dir && (
        <Link href={href("path", parentOf(dir))} className="flex items-center gap-3 px-4 py-2.5 text-sm text-muted hover:bg-accent">
          <Folder className="h-4 w-4 shrink-0" />
          ..
          <LinkPending className="ml-auto" />
        </Link>
      )}
      {sorted.map((e) => {
        const p = join(dir, e.name);
        const isDir = e.type === "dir";
        return (
          <Link
            key={e.name}
            href={href(isDir ? "path" : "file", p)}
            className="flex items-center gap-3 px-4 py-2.5 text-sm text-foreground hover:bg-accent"
          >
            {isDir ? <Folder className="h-4 w-4 shrink-0 text-primary" /> : <File className="h-4 w-4 shrink-0 text-muted" />}
            <span className="min-w-0 flex-1 truncate">{e.name}</span>
            <LinkPending />
            {!isDir && <span className="shrink-0 text-xs text-muted tabular-nums">{formatSize(e.size)}</span>}
          </Link>
        );
      })}
    </Card>
  );
}

/** Text files only (the engine answers 413/415 otherwise, shown as an error). */
function FileView({ file }: { file: KillaFile }) {
  const markdown = /\.(md|markdown)$/i.test(file.path);
  return (
    <FileEditor key={file.path} path={file.path} content={file.content}>
      {markdown ? (
        <div className="p-4">
          <Markdown text={file.content} />
        </div>
      ) : (
        <pre className="max-h-[70vh] overflow-auto p-4 font-mono text-xs leading-relaxed text-foreground whitespace-pre">
          {file.content}
        </pre>
      )}
    </FileEditor>
  );
}
