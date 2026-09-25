import { SkeletonBox, SkeletonHeader, SkeletonPage } from "@/components/skeleton";

/** Habits board: header + a grid of habit cards. */
export default function HabitsLoading() {
  return (
    <SkeletonPage label="Memuat kebiasaan">
      <SkeletonHeader action="w-72" />
      <div className="mb-3 h-4 w-28 rounded bg-accent" />
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <SkeletonBox key={i} className="space-y-3 p-4">
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 rounded-full bg-accent" />
              <div className="flex-1 space-y-1.5">
                <div className="h-4 w-32 rounded bg-accent" />
                <div className="h-3 w-20 rounded bg-accent" />
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="h-14 w-14 rounded-full bg-accent" />
              <div className="h-4 w-28 rounded bg-accent" />
            </div>
            <div className="h-9 rounded-lg bg-accent" />
          </SkeletonBox>
        ))}
      </div>
    </SkeletonPage>
  );
}
