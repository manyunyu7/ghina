/** Skeleton while a Killa page loads (header, tabs, message bubbles). */
export default function KillaLoading() {
  const rows = [{ w: "60%", me: true }, { w: "80%" }, { w: "45%", me: true }, { w: "70%" }];
  return (
    <div className="animate-pulse" aria-busy="true" aria-label="Memuat Killa">
      <div className="mb-6">
        <div className="h-7 w-24 rounded-lg bg-accent" />
        <div className="mt-2 h-4 w-72 rounded bg-accent" />
      </div>
      <div className="mb-5 h-9 w-56 rounded-lg bg-accent" />
      <div className="space-y-3 rounded-card border border-border bg-card p-4">
        {rows.map((r, i) => (
          <div key={i} className={r.me ? "flex justify-end" : "flex"}>
            <div className="h-14 rounded-2xl bg-accent" style={{ width: r.w }} />
          </div>
        ))}
      </div>
    </div>
  );
}
