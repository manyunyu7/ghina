import { SkeletonBox, SkeletonHeader, SkeletonPage, SkeletonPills } from "@/components/skeleton";

/** Transactions: summary strip, search + filters, day-grouped list. */
export default function TransactionsLoading() {
  return (
    <SkeletonPage label="Memuat transaksi">
      <SkeletonHeader action="w-40" />
      <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
        {[0, 1, 2].map((i) => (
          <SkeletonBox key={i} className="h-[84px]" />
        ))}
      </div>
      <div className="mb-6 space-y-3">
        <div className="h-10 w-full rounded-lg bg-accent" />
        <SkeletonPills widths={[110, 120, 140, 120, 100]} />
      </div>
      <div className="space-y-6">
        {[3, 2].map((rows, g) => (
          <div key={g}>
            <div className="mb-2 h-3 w-28 rounded bg-accent" />
            <SkeletonBox className="divide-y divide-border">
              {Array.from({ length: rows }, (_, i) => (
                <div key={i} className="flex items-center gap-3 p-4">
                  <div className="h-10 w-10 shrink-0 rounded-full bg-accent" />
                  <div className="min-w-0 flex-1 space-y-2">
                    <div className="h-4 w-40 max-w-full rounded bg-accent" />
                    <div className="h-3 w-24 rounded bg-accent" />
                  </div>
                  <div className="h-4 w-20 rounded bg-accent" />
                </div>
              ))}
            </SkeletonBox>
          </div>
        ))}
      </div>
    </SkeletonPage>
  );
}
