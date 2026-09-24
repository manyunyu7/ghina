import { SkeletonBox, SkeletonHeader, SkeletonPage } from "@/components/skeleton";

/** Reports: period picker, 4 stat cards, income/expense + donut, trend charts. */
export default function ReportsLoading() {
  return (
    <SkeletonPage label="Memuat laporan">
      <SkeletonHeader action="w-44" />
      <div className="space-y-6">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {[0, 1, 2, 3].map((i) => (
            <SkeletonBox key={i} className="h-[84px]" />
          ))}
        </div>
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
          <SkeletonBox className="h-80 lg:col-span-3" />
          <SkeletonBox className="h-80 lg:col-span-2" />
        </div>
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <SkeletonBox className="h-72" />
          <SkeletonBox className="h-72" />
        </div>
      </div>
    </SkeletonPage>
  );
}
