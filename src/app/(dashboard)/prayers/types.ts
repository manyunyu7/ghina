/** A prayer entry as passed to client components (serializable). */
export type PrayerEntryDTO = {
  date: string;
  prayer: string;
  status: string;
  qobliyah: boolean;
  badiyah: boolean;
  rakaat: number | null;
  /** ISO timestamp */
  prayedAt: string | null;
  note: string | null;
};

type Row = {
  date: string;
  prayer: string;
  status: string;
  qobliyah: boolean;
  badiyah: boolean;
  rakaat: number | null;
  prayedAt: Date | null;
  note: string | null;
};

export function toDTO(r: Row): PrayerEntryDTO {
  return {
    date: r.date,
    prayer: r.prayer,
    status: r.status,
    qobliyah: r.qobliyah,
    badiyah: r.badiyah,
    rakaat: r.rakaat,
    prayedAt: r.prayedAt ? r.prayedAt.toISOString() : null,
    note: r.note,
  };
}

/** Prisma `select` for the fields above. */
export const PRAYER_SELECT = {
  date: true,
  prayer: true,
  status: true,
  qobliyah: true,
  badiyah: true,
  rakaat: true,
  prayedAt: true,
  note: true,
} as const;

/** Group entries by date: date -> prayer -> entry. */
export function byDate(entries: PrayerEntryDTO[]): Record<string, Record<string, PrayerEntryDTO>> {
  const out: Record<string, Record<string, PrayerEntryDTO>> = {};
  for (const e of entries) (out[e.date] ??= {})[e.prayer] = e;
  return out;
}

/** "Rabu, 24 September 2026" */
export function formatLong(key: string): string {
  const [y, m, d] = key.split("-").map(Number);
  return new Intl.DateTimeFormat("id-ID", { weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(
    new Date(y, m - 1, d),
  );
}
