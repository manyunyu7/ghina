import { Tags, ArrowDownCircle, ArrowUpCircle } from "lucide-react";
import { requireUser } from "@/lib/auth-helpers";
import { prisma } from "@/lib/prisma";
import { Card, CardContent } from "@/components/ui/card";
import { Badge, EmptyState, PageHeader } from "@/components/ui/misc";
import { CategoryIcon } from "@/components/icon";
import { AddCategoryButton } from "./add-category-button";
import { CategoryActions } from "./category-actions";
import { SeedButton } from "./seed-button";

type CategoryRow = {
  id: string;
  name: string;
  type: string;
  color: string;
  icon: string;
  _count: { transactions: number };
};

function CategoryItem({ category }: { category: CategoryRow }) {
  const count = category._count.transactions;
  return (
    <div className="flex items-center justify-between gap-3 rounded-lg border border-border bg-surface p-3">
      <div className="flex min-w-0 items-center gap-3">
        <div
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full"
          style={{ background: `${category.color}1a`, color: category.color }}
        >
          <CategoryIcon name={category.icon} className="h-5 w-5" />
        </div>
        <div className="min-w-0">
          <p className="truncate font-medium text-foreground">{category.name}</p>
          <p className="text-xs text-muted">
            {count} transaction{count === 1 ? "" : "s"}
          </p>
        </div>
      </div>
      <CategoryActions
        category={{
          id: category.id,
          name: category.name,
          type: category.type,
          color: category.color,
          icon: category.icon,
        }}
        transactionCount={count}
      />
    </div>
  );
}

function CategorySection({
  title,
  icon: Icon,
  accent,
  categories,
  defaultType,
}: {
  title: string;
  icon: React.ComponentType<{ className?: string }>;
  accent: string;
  categories: CategoryRow[];
  defaultType: "expense" | "income";
}) {
  return (
    <Card>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Icon className={accent} />
            <h2 className="text-base font-semibold text-foreground">{title}</h2>
            <Badge>{categories.length}</Badge>
          </div>
          <AddCategoryButton label="Add" variant="ghost" size="sm" defaultType={defaultType} />
        </div>

        {categories.length === 0 ? (
          <p className="rounded-lg border border-dashed border-border bg-surface px-4 py-8 text-center text-sm text-muted">
            No {defaultType} categories yet.
          </p>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {categories.map((c) => (
              <CategoryItem key={c.id} category={c} />
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export default async function CategoriesPage() {
  const user = await requireUser();

  const categories = await prisma.category.findMany({
    where: { userId: user.id },
    include: { _count: { select: { transactions: true } } },
    orderBy: { name: "asc" },
  });

  const expense = categories.filter((c) => c.type === "expense");
  const income = categories.filter((c) => c.type === "income");

  return (
    <div>
      <PageHeader
        title="Categories"
        description="Organize your income and expenses into categories."
        action={<AddCategoryButton />}
      />

      {categories.length === 0 ? (
        <EmptyState
          icon={Tags}
          title="No categories yet"
          description="Get started quickly by adding a curated set of common categories, or create your own."
          action={
            <div className="flex flex-col items-center gap-3">
              <SeedButton />
              <AddCategoryButton label="Create your own" variant="outline" />
            </div>
          }
        />
      ) : (
        <div className="space-y-6">
          <CategorySection
            title="Expense"
            icon={ArrowDownCircle}
            accent="h-5 w-5 text-expense"
            categories={expense}
            defaultType="expense"
          />
          <CategorySection
            title="Income"
            icon={ArrowUpCircle}
            accent="h-5 w-5 text-income"
            categories={income}
            defaultType="income"
          />
        </div>
      )}
    </div>
  );
}
