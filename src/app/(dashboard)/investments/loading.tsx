import { SkeletonBox, SkeletonHeader, SkeletonPage } from "@/components/skeleton";

/** Portfolio: summary card + stats, two charts, holdings rows. */
export default function InvestmentsLoading() {
  return (
    <SkeletonPage label="Memuat portofolio">
      <SkeletonHeader action="w-64" />
      <div className="mb-6 grid gap-4 lg:grid-cols-3">
        <div className="h-40 rounded-card bg-accent" />
        <div className="grid grid-cols-2 gap-3 lg:col-span-2 lg:grid-cols-3">
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <SkeletonBox key={i} className="h-[76px]" />
          ))}
        </div>
      </div>
      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        <SkeletonBox className="h-64" />
        <SkeletonBox className="h-64" />
      </div>
      <div className="space-y-3">
        {[0, 1, 2, 3].map((i) => (
          <SkeletonBox key={i} className="h-16" />
        ))}
      </div>
    </SkeletonPage>
  );
}
