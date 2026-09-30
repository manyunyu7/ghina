import type { Metadata } from "next";
import { AlertTriangle, GitCommitHorizontal } from "lucide-react";
import { Card } from "@/components/ui/card";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { KillaError, killaEngine, requireKillaUser, type KillaCommit } from "@/lib/killa";
import { KillaNav } from "../killa-nav";

export const metadata: Metadata = { title: "Commit Killa — Ghina" };

const dateFmt = new Intl.DateTimeFormat("id-ID", {
  day: "numeric",
  month: "short",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  timeZone: "Asia/Jakarta",
});

function formatDate(s: string) {
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? s : dateFmt.format(d);
}

/** Recent commits of Killa's workspace repo (GET /v1/git/log). */
export default async function KillaCommitsPage() {
  await requireKillaUser();
  let commits: KillaCommit[] = [];
  let error: string | null = null;
  try {
    commits = await killaEngine.commits(100);
  } catch (e) {
    if (!(e instanceof KillaError)) throw e;
    error = e.message;
  }

  return (
    <div>
      <PageHeader title="Killa" description="Riwayat commit workspace Killa." />
      <KillaNav />
      {error ? (
        <div role="alert" className="flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{error}</span>
        </div>
      ) : commits.length === 0 ? (
        <EmptyState icon={GitCommitHorizontal} title="Belum ada commit" />
      ) : (
        <Card className="divide-y divide-border-soft overflow-hidden">
          {commits.map((c) => (
            <div key={c.hash} className="flex items-start gap-3 px-4 py-3">
              <GitCommitHorizontal className="mt-0.5 h-4 w-4 shrink-0 text-muted" />
              <div className="min-w-0 flex-1">
                <p className="break-words text-sm font-medium text-foreground">{c.subject}</p>
                <p className="mt-0.5 text-xs text-muted">
                  {c.author} · {formatDate(c.date)}
                </p>
              </div>
              <code className="shrink-0 rounded bg-accent px-1.5 py-0.5 font-mono text-xs text-muted">{c.hash.slice(0, 7)}</code>
            </div>
          ))}
        </Card>
      )}
    </div>
  );
}
