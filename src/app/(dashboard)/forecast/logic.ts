import { advanceCycle } from "../subscriptions/presets";

/**
 * All billing occurrences of a subscription that fall within [start, end].
 * Rolls the anchor forward by whole cycles, so weekly subs can land more than
 * once in a month while monthly/yearly land at most once.
 */
export function occurrencesInMonth(
  anchor: Date | string,
  cycle: string,
  start: Date,
  end: Date,
): Date[] {
  const out: Date[] = [];
  let d = new Date(anchor);

  let guard = 0;
  while (d < start && guard < 2000) {
    d = advanceCycle(d, cycle);
    guard++;
  }
  guard = 0;
  while (d <= end && guard < 2000) {
    out.push(new Date(d));
    d = advanceCycle(d, cycle);
    guard++;
  }
  return out;
}
