import { SkeletonBox, SkeletonHeader, SkeletonPage, SkeletonPills } from "@/components/skeleton";

/** Habit detail: header, today card + stat tiles, heatmap, charts, log list. */
export default function HabitDetailLoading() {
  return (
    <SkeletonPage label="Memuat detail kebiasaan">
      <SkeletonHeader action="w-24" />
      <div className="mb-6 grid gap-4 lg:grid-cols-3">
        <SkeletonBox className="h-56" />
        <SkeletonBox className="h-56 lg:col-span-2" />
      </div>
      <SkeletonPills widths={[80, 72, 120]} className="mb-4" />
      <SkeletonBox className="mb-6 h-72" />
      <div className="grid gap-4 lg:grid-cols-2">
        <SkeletonBox className="h-64" />
        <SkeletonBox className="h-64" />
      </div>
    </SkeletonPage>
  );
}
