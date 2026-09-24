/** Skeleton while the notes page loads (header, tabs, masonry cards). */
export default function NotesLoading() {
  const heights = [140, 220, 110, 180, 260, 130, 200, 150];
  return (
    <div className="animate-pulse" aria-busy="true" aria-label="Memuat catatan">
      <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <div className="h-7 w-32 rounded-lg bg-accent" />
          <div className="mt-2 h-4 w-56 rounded bg-accent" />
        </div>
        <div className="h-10 w-36 rounded-lg bg-accent" />
      </div>
      <div className="mb-4 h-10 w-full rounded-lg bg-accent" />
      <div className="mb-6 flex gap-2">
        {[64, 96, 72, 56].map((w, i) => (
          <div key={i} className="h-8 rounded-full bg-accent" style={{ width: w }} />
        ))}
      </div>
      <div className="columns-1 gap-4 sm:columns-2 lg:columns-3 xl:columns-4">
        {heights.map((h, i) => (
          <div key={i} className="mb-4 break-inside-avoid rounded-card border border-border bg-card" style={{ height: h }} />
        ))}
      </div>
    </div>
  );
}
