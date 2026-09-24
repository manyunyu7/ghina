/** Route-level fallback for every dashboard page: navigation shows this instantly. */
export default function DashboardLoading() {
  return (
    <div className="animate-pulse" aria-busy="true" aria-label="Memuat">
      <span className="nav-progress" aria-hidden />
      <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <div className="h-7 w-40 rounded-lg bg-accent" />
          <div className="mt-2 h-4 w-64 rounded bg-accent" />
        </div>
        <div className="h-10 w-32 rounded-lg bg-accent" />
      </div>
      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="h-24 rounded-card border border-border bg-card" />
        ))}
      </div>
      <div className="grid gap-4 lg:grid-cols-3">
        <div className="h-72 rounded-card border border-border bg-card lg:col-span-2" />
        <div className="h-72 rounded-card border border-border bg-card" />
      </div>
      <div className="mt-4 space-y-3">
        {[0, 1, 2, 3, 4].map((i) => (
          <div key={i} className="h-14 rounded-card border border-border bg-card" />
        ))}
      </div>
    </div>
  );
}
