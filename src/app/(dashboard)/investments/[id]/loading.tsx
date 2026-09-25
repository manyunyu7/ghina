import { SkeletonBox, SkeletonPage } from "@/components/skeleton";

/** Asset detail: quote header, position + P/L cards, trade rows. */
export default function AssetDetailLoading() {
  return (
    <SkeletonPage label="Memuat aset">
      <div className="mb-6 h-4 w-24 rounded bg-accent" />
      <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="h-7 w-32 rounded-lg bg-accent" />
          <div className="mt-2 h-4 w-48 rounded bg-accent" />
          <div className="mt-3 h-9 w-40 rounded-lg bg-accent" />
        </div>
        <div className="h-10 w-56 rounded-lg bg-accent" />
      </div>
      <div className="mb-6 grid gap-4 lg:grid-cols-3">
        <SkeletonBox className="h-56" />
        <SkeletonBox className="h-56 lg:col-span-2" />
      </div>
      <div className="space-y-2">
        {[0, 1, 2, 3].map((i) => (
          <SkeletonBox key={i} className="h-14" />
        ))}
      </div>
    </SkeletonPage>
  );
}
