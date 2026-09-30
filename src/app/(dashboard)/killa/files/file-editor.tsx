"use client";

import * as React from "react";
import { Check, GitCommitHorizontal, Pencil, Save, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { KILLA_FILE_MAX } from "@/lib/schemas";
import { commitKillaWorkspace, saveKillaFile } from "../actions";

/**
 * A workspace text file: read view (`children`, rendered by the server) or an edit mode
 * (monospace textarea → PUT /v1/workspace/file), plus a workspace commit (POST /v1/git/commit).
 */
export function FileEditor({ path, content, children }: { path: string; content: string; children: React.ReactNode }) {
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState(content);
  const [error, setError] = React.useState<string | null>(null);
  const [notice, setNotice] = React.useState<string | null>(null);
  const [saving, startSave] = React.useTransition();
  const dirty = draft !== content;

  function startEdit() {
    setDraft(content);
    setError(null);
    setNotice(null);
    setEditing(true);
  }

  function cancel() {
    if (dirty && !window.confirm("Buang perubahan yang belum disimpan?")) return;
    setEditing(false);
    setError(null);
  }

  function save() {
    setError(null);
    setNotice(null);
    startSave(async () => {
      const res = await saveKillaFile({ path, content: draft });
      if (res.ok) {
        setEditing(false);
        setNotice("Tersimpan.");
      } else setError(res.error);
    });
  }

  return (
    <div className="space-y-3">
      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-center gap-2 border-b border-border px-4 py-2">
          <span className="min-w-0 flex-1 truncate font-mono text-xs text-muted">{path}</span>
          {editing ? (
            <>
              <Button size="sm" variant="ghost" onClick={cancel} disabled={saving}>
                <X className="h-4 w-4" />
                Batal
              </Button>
              <Button size="sm" onClick={save} loading={saving} disabled={!dirty}>
                {!saving && <Save className="h-4 w-4" />}
                {saving ? "Menyimpan…" : "Simpan"}
              </Button>
            </>
          ) : (
            <Button size="sm" variant="outline" onClick={startEdit}>
              <Pencil className="h-4 w-4" />
              Edit
            </Button>
          )}
        </div>
        {editing ? (
          <textarea
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if ((e.metaKey || e.ctrlKey) && e.key === "s") {
                e.preventDefault();
                if (dirty && !saving) save();
              }
            }}
            maxLength={KILLA_FILE_MAX}
            spellCheck={false}
            aria-label={`Isi ${path}`}
            className="block h-[70vh] w-full resize-y bg-surface p-4 font-mono text-xs leading-relaxed text-foreground outline-none"
          />
        ) : (
          children
        )}
      </Card>
      {error && <p className="text-sm text-expense">{error}</p>}
      {notice && (
        <p className="inline-flex items-center gap-1 text-sm text-income">
          <Check className="h-4 w-4" />
          {notice}
        </p>
      )}
      <CommitBar />
    </div>
  );
}

/** Commit the whole workspace with an optional message; shows the resulting hash. */
function CommitBar() {
  const [message, setMessage] = React.useState("");
  const [result, setResult] = React.useState<{ hash: string | null } | null>(null);
  const [error, setError] = React.useState<string | null>(null);
  const [pending, startTransition] = React.useTransition();

  function commit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setResult(null);
    startTransition(async () => {
      const res = await commitKillaWorkspace(message);
      if (res.ok) {
        setResult({ hash: res.hash });
        setMessage("");
      } else setError(res.error);
    });
  }

  return (
    <Card className="p-3">
      <form onSubmit={commit} className="flex flex-wrap items-center gap-2">
        <Input
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          maxLength={500}
          placeholder="Pesan commit (opsional)"
          aria-label="Pesan commit"
          className="h-9 min-w-48 flex-1"
        />
        <Button type="submit" size="sm" variant="outline" loading={pending}>
          {!pending && <GitCommitHorizontal className="h-4 w-4" />}
          Commit
        </Button>
      </form>
      {error && <p className="mt-2 text-sm text-expense">{error}</p>}
      {result && (
        <p className="mt-2 text-sm text-muted">
          {result.hash ? (
            <>
              Commit dibuat:{" "}
              <code className="rounded bg-accent px-1.5 py-0.5 font-mono text-xs text-foreground">{result.hash.slice(0, 12)}</code>
            </>
          ) : (
            "Tidak ada perubahan untuk di-commit."
          )}
        </p>
      )}
    </Card>
  );
}
