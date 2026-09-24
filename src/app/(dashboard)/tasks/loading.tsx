import { SkeletonBox, SkeletonHeader, SkeletonPage, SkeletonPills } from "@/components/skeleton";

/** Tasks board: area tabs, filter chips, one column per area with FIRE/WANT/SHOULD cells. */
export default function TasksLoading() {
  return (
    <SkeletonPage label="Memuat tugas">
      <SkeletonHeader action="w-56" />
      <SkeletonPills widths={[88, 104, 96, 80, 72]} className="mb-3" />
      <SkeletonPills widths={[64, 88, 80, 96, 72]} className="mb-4" />
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        {[0, 1, 2].map((c) => (
          <SkeletonBox key={c} className="space-y-3 p-3">
            <div className="h-5 w-32 rounded bg-accent" />
            {[3, 2, 2].map((n, b) => (
              <div key={b} className="space-y-2 rounded-lg bg-accent/50 p-2">
                <div className="h-3 w-20 rounded bg-accent" />
                {Array.from({ length: n }, (_, i) => (
                  <div key={i} className="h-12 rounded-lg bg-accent" />
                ))}
              </div>
            ))}
          </SkeletonBox>
        ))}
      </div>
    </SkeletonPage>
  );
}
