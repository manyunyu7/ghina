import { Utensils, Flame } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { Card } from "@/components/ui/card";
import { Badge, EmptyState, PageHeader } from "@/components/ui/misc";
import { formatDate } from "@/lib/utils";
import { mealLabel } from "./constants";
import { AddFoodButton } from "./add-food-button";
import { FoodActions } from "./food-actions";
import type { FoodFormData } from "./food-form";

function dayKey(d: Date) {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}
const timeOf = (d: Date) => new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(d);

export default async function FoodPage() {
  const user = await requireUser();

  const entries = await prisma.foodLog.findMany({
    where: { userId: user.id },
    orderBy: { date: "desc" },
    take: 300,
  });

  if (entries.length === 0) {
    return (
      <div>
        <PageHeader title="Food Log" description="Log your meals with a photo, calories, and notes." />
        <EmptyState
          icon={Utensils}
          title="No meals logged yet"
          description="Snap a photo of what you eat, add the calories if you know them, and build your food diary."
          action={<AddFoodButton />}
        />
      </div>
    );
  }

  const todayK = dayKey(new Date());
  const todayEntries = entries.filter((e) => dayKey(e.date) === todayK);
  const todayCalories = todayEntries.reduce((sum, e) => sum + (e.calories ?? 0), 0);

  // Group by day (entries already sorted desc by date)
  const groups: { key: string; date: Date; items: typeof entries }[] = [];
  for (const e of entries) {
    const k = dayKey(e.date);
    const last = groups[groups.length - 1];
    if (last && last.key === k) last.items.push(e);
    else groups.push({ key: k, date: e.date, items: [e] });
  }

  return (
    <div>
      <PageHeader
        title="Food Log"
        description="Log your meals with a photo, calories, and notes."
        action={<AddFoodButton />}
      />

      {/* Today summary */}
      <Card className="mb-6 flex items-center gap-4 p-4">
        <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-expense-soft text-expense">
          <Flame className="h-5 w-5" />
        </div>
        <div>
          <p className="text-sm text-muted">Today</p>
          <p className="text-xl font-bold text-foreground">
            {todayCalories > 0 ? `${todayCalories.toLocaleString()} kcal` : `${todayEntries.length} logged`}
          </p>
        </div>
        <p className="ml-auto text-sm text-muted">
          {todayEntries.length} {todayEntries.length === 1 ? "meal" : "meals"} today
        </p>
      </Card>

      <div className="space-y-6">
        {groups.map((g) => (
          <div key={g.key}>
            <h3 className="mb-2 text-sm font-semibold text-muted">
              {g.key === todayK ? "Today" : formatDate(g.date, { weekday: "short", day: "numeric", month: "short" })}
            </h3>
            <div className="grid gap-3 sm:grid-cols-2">
              {g.items.map((e) => {
                const formData: FoodFormData = {
                  id: e.id,
                  date: e.date.toISOString(),
                  name: e.name,
                  meal: e.meal,
                  calories: e.calories,
                  photoUrl: e.photoUrl,
                  note: e.note,
                };
                return (
                  <Card key={e.id} className="overflow-hidden">
                    {e.photoUrl && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={e.photoUrl} alt={e.name} className="h-40 w-full object-cover" />
                    )}
                    <div className="flex items-start gap-3 p-4">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="font-medium text-foreground">{e.name}</p>
                          {mealLabel(e.meal) && <Badge variant="primary">{mealLabel(e.meal)}</Badge>}
                        </div>
                        <p className="mt-0.5 text-xs text-muted">
                          {timeOf(e.date)}
                          {e.calories != null && <span className="font-medium text-foreground"> · {e.calories.toLocaleString()} kcal</span>}
                        </p>
                        {e.note && <p className="mt-1 text-sm text-muted">{e.note}</p>}
                      </div>
                      <FoodActions entry={formData} />
                    </div>
                  </Card>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
