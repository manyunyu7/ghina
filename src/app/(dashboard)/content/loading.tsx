import { SkeletonBox, SkeletonHeader, SkeletonPage } from "@/components/skeleton";

/** Content planner: tabs + kanban columns (also used by /content/accounts). */
export default function ContentLoading() {
  return (
    <SkeletonPage label="Memuat konten">
      <SkeletonHeader action="w-36" />
      <div className="mb-5 h-9 w-full max-w-md rounded-lg bg-accent" />
      <div className="mb-4 h-9 w-full rounded-lg bg-accent" />
      <div className="flex gap-4 overflow-hidden">
        {[3, 2, 2, 1, 2].map((n, c) => (
          <SkeletonBox key={c} className="w-72 shrink-0 space-y-2 p-3">
            <div className="h-5 w-24 rounded bg-accent" />
            {Array.from({ length: n }, (_, i) => (
              <div key={i} className="h-24 rounded-lg bg-accent" />
            ))}
          </SkeletonBox>
        ))}
      </div>
    </SkeletonPage>
  );
}
