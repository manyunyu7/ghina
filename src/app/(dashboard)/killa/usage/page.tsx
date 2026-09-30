import type { Metadata } from "next";
import { AlertTriangle } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/misc";
import { KillaError, killaEngine, requireKillaUser, type KillaUsage } from "@/lib/killa";
import { KillaNav } from "../killa-nav";
import { UsageBars } from "./usage-chart";

export const metadata: Metadata = { title: "Usage Killa — Ghina" };

const DAYS = 30;
const intFmt = new Intl.NumberFormat("id-ID");
const usd = (v: number) => `$${v.toFixed(v >= 10 ? 2 : 3)}`;
const compact = new Intl.NumberFormat("id-ID", { notation: "compact", maximumFractionDigits: 1 });

/** Killa token/cost accounting over the last 30 days (GET /v1/usage) — all chats, WA and Ghina. */
export default async function KillaUsagePage() {
  await requireKillaUser();
  let usage: KillaUsage | null = null;
  let error: string | null = null;
  try {
    usage = await killaEngine.usage(DAYS);
  } catch (e) {
    if (!(e instanceof KillaError)) throw e;
    error = e.message;
  }

  const models = usage ? Object.entries(usage.byModel).sort((a, b) => b[1].costUsd - a[1].costUsd) : [];
  const t = usage?.total;

  return (
    <div>
      <PageHeader title="Killa" description={`Pemakaian token & perkiraan biaya ${DAYS} hari terakhir.`} />
      <KillaNav />
      {error || !usage || !t ? (
        <div role="alert" className="flex items-start gap-2 rounded-lg bg-expense-soft px-3 py-2 text-sm text-expense">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{error ?? "Data usage tidak tersedia"}</span>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Stat label="Perkiraan biaya" value={usd(t.costUsd)} />
            <Stat label="Giliran (turn)" value={intFmt.format(t.turns)} />
            <Stat label="Token output" value={compact.format(t.outputTokens)} />
            <Stat
              label="Token input"
              value={compact.format(t.inputTokens + t.cacheReadTokens + t.cacheCreationTokens)}
              hint={`${compact.format(t.cacheReadTokens)} dari cache`}
            />
          </div>

          <Card>
            <CardHeader>
              <CardTitle>Biaya per hari</CardTitle>
            </CardHeader>
            <CardContent>
              <UsageBars days={usage.days} />
            </CardContent>
          </Card>

          <Card className="overflow-hidden">
            <CardHeader>
              <CardTitle>Per model</CardTitle>
            </CardHeader>
            {models.length === 0 ? (
              <p className="px-4 pb-4 text-sm text-muted">Belum ada pemakaian.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs text-muted">
                    <tr className="border-b border-border-soft">
                      <th className="px-4 py-2 font-medium">Model</th>
                      <th className="px-4 py-2 text-right font-medium">Turn</th>
                      <th className="px-4 py-2 text-right font-medium">Input</th>
                      <th className="px-4 py-2 text-right font-medium">Cache</th>
                      <th className="px-4 py-2 text-right font-medium">Output</th>
                      <th className="px-4 py-2 text-right font-medium">Biaya</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-soft">
                    {models.map(([name, m]) => (
                      <tr key={name}>
                        <td className="px-4 py-2 font-mono text-xs text-foreground">{name}</td>
                        <td className="px-4 py-2 text-right tabular-nums">{intFmt.format(m.turns)}</td>
                        <td className="px-4 py-2 text-right tabular-nums">{compact.format(m.inputTokens + m.cacheCreationTokens)}</td>
                        <td className="px-4 py-2 text-right tabular-nums">{compact.format(m.cacheReadTokens)}</td>
                        <td className="px-4 py-2 text-right tabular-nums">{compact.format(m.outputTokens)}</td>
                        <td className="px-4 py-2 text-right font-medium tabular-nums">{usd(m.costUsd)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>

          <p className="text-xs text-muted">
            Biaya adalah perkiraan menurut harga API (dilaporkan Claude CLI), bukan tagihan — dengan langganan, angkanya
            hanya nosional. Mencakup semua percakapan (WhatsApp dan Ghina) termasuk flush memori.
          </p>
        </div>
      )}
    </div>
  );
}

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card className="px-4 py-3">
      <p className="text-xs text-muted">{label}</p>
      <p className="mt-1 text-lg font-semibold tabular-nums text-foreground">{value}</p>
      {hint && <p className="text-[11px] text-muted">{hint}</p>}
    </Card>
  );
}
