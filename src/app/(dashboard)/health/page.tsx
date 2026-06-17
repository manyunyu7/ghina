import { HeartPulse, Scale, Activity, ArrowUp, ArrowDown } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState, PageHeader } from "@/components/ui/misc";
import { formatDate, cn } from "@/lib/utils";
import { classifyBP } from "./bp";
import { WeightChart, BloodPressureChart } from "./health-charts";
import { AddEntryButton } from "./add-entry-button";
import { EntryActions } from "./entry-actions";
import type { HealthFormData } from "./health-form";

const shortLabel = (d: Date) =>
  new Intl.DateTimeFormat("en-US", { day: "numeric", month: "short" }).format(d);

export default async function HealthPage() {
  const user = await requireUser();

  const entries = await prisma.healthEntry.findMany({
    where: { userId: user.id },
    orderBy: { date: "desc" },
    take: 365,
  });

  if (entries.length === 0) {
    return (
      <div>
        <PageHeader title="Health" description="Track your body weight and blood pressure over time." />
        <EmptyState
          icon={HeartPulse}
          title="No measurements yet"
          description="Log your weight or blood pressure to start seeing your trends and history."
          action={<AddEntryButton />}
        />
      </div>
    );
  }

  const weights = entries.filter((e) => e.weight != null);
  const bps = entries.filter((e) => e.systolic != null && e.diastolic != null);
  const pulses = entries.filter((e) => e.pulse != null);

  const latestWeight = weights[0]?.weight ?? null;
  const prevWeight = weights[1]?.weight ?? null;
  const weightDelta = latestWeight != null && prevWeight != null ? latestWeight - prevWeight : null;

  const latestBp = bps[0] ?? null;
  const bpCategory = classifyBP(latestBp?.systolic, latestBp?.diastolic);
  const latestPulse = pulses[0]?.pulse ?? null;

  // Charts: ascending, capped to last 30 points
  const weightData = weights
    .slice(0, 30)
    .reverse()
    .map((e) => ({ label: shortLabel(e.date), weight: e.weight as number }));
  const bpData = bps
    .slice(0, 30)
    .reverse()
    .map((e) => ({ label: shortLabel(e.date), systolic: e.systolic as number, diastolic: e.diastolic as number }));

  return (
    <div>
      <PageHeader
        title="Health"
        description="Track your body weight and blood pressure over time."
        action={<AddEntryButton />}
      />

      {/* Latest stats */}
      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <Card className="p-4">
          <div className="mb-3 flex h-9 w-9 items-center justify-center rounded-lg bg-primary-soft text-primary">
            <Scale className="h-5 w-5" />
          </div>
          <p className="text-sm text-muted">Weight</p>
          <p className="text-xl font-bold text-foreground">
            {latestWeight != null ? `${latestWeight} kg` : "—"}
          </p>
          {weightDelta != null && weightDelta !== 0 && (
            <p className={cn("mt-0.5 inline-flex items-center gap-0.5 text-xs font-medium", weightDelta > 0 ? "text-expense" : "text-income")}>
              {weightDelta > 0 ? <ArrowUp className="h-3 w-3" /> : <ArrowDown className="h-3 w-3" />}
              {Math.abs(weightDelta).toFixed(1)} kg vs last
            </p>
          )}
        </Card>

        <Card className="p-4">
          <div className="mb-3 flex h-9 w-9 items-center justify-center rounded-lg bg-expense-soft text-expense">
            <HeartPulse className="h-5 w-5" />
          </div>
          <p className="text-sm text-muted">Blood pressure</p>
          <p className="text-xl font-bold text-foreground">
            {latestBp ? `${latestBp.systolic}/${latestBp.diastolic}` : "—"}
          </p>
          {bpCategory && (
            <span className={cn("mt-1 inline-flex rounded-full px-2 py-0.5 text-xs font-medium", bpCategory.className)}>
              {bpCategory.label}
            </span>
          )}
        </Card>

        <Card className="p-4">
          <div className="mb-3 flex h-9 w-9 items-center justify-center rounded-lg bg-income-soft text-income">
            <Activity className="h-5 w-5" />
          </div>
          <p className="text-sm text-muted">Pulse</p>
          <p className="text-xl font-bold text-foreground">{latestPulse != null ? `${latestPulse} bpm` : "—"}</p>
        </Card>
      </div>

      {/* Charts */}
      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        {weightData.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle>Weight trend</CardTitle>
            </CardHeader>
            <CardContent>
              <WeightChart data={weightData} />
            </CardContent>
          </Card>
        )}
        {bpData.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle>Blood pressure trend</CardTitle>
            </CardHeader>
            <CardContent>
              <BloodPressureChart data={bpData} />
            </CardContent>
          </Card>
        )}
      </div>

      {/* History */}
      <Card>
        <CardHeader>
          <CardTitle>History</CardTitle>
        </CardHeader>
        <CardContent className="pt-0">
          <ul className="divide-y divide-border-soft">
            {entries.map((e) => {
              const cat = classifyBP(e.systolic, e.diastolic);
              const formData: HealthFormData = {
                id: e.id,
                date: e.date.toISOString(),
                weight: e.weight,
                systolic: e.systolic,
                diastolic: e.diastolic,
                pulse: e.pulse,
                note: e.note,
              };
              return (
                <li key={e.id} className="flex items-center justify-between gap-3 py-3">
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-foreground">{formatDate(e.date)}</p>
                    <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
                      {e.weight != null && <span>{e.weight} kg</span>}
                      {e.systolic != null && e.diastolic != null && (
                        <span className="inline-flex items-center gap-1.5">
                          {e.systolic}/{e.diastolic}
                          {cat && <span className={cn("rounded-full px-1.5 py-0.5", cat.className)}>{cat.label}</span>}
                        </span>
                      )}
                      {e.pulse != null && <span>{e.pulse} bpm</span>}
                      {e.note && <span className="text-muted-soft">· {e.note}</span>}
                    </div>
                  </div>
                  <EntryActions entry={formData} />
                </li>
              );
            })}
          </ul>
        </CardContent>
      </Card>
    </div>
  );
}
