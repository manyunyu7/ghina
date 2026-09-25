import type { User } from "@prisma/client";
import type { SyncEntity } from "@/lib/tombstones";
import { parsePhotos } from "@/lib/photos";
import { parseRecurrence, parseSchedule } from "@/lib/tasks";
import { parseAudio, parseChecklist, parseImageList, parseLabelIds, parseLinks } from "@/lib/notes";
import { parseAssetLinks, parseMetrics, parseSponsor } from "@/lib/content";
import { parseHabitSchedule, parseHabitTarget, parseReminders, parseTriggers } from "@/lib/habits";

/** Wire fields per entity (Prisma field names minus userId) — see docs/mobile-sync.md. */
export const ENTITY_FIELDS: Record<SyncEntity, readonly string[]> = {
  wallets: ["id", "name", "type", "balance", "currency", "color", "icon", "archived", "createdAt", "updatedAt"],
  categories: ["id", "name", "type", "color", "icon", "createdAt", "updatedAt"],
  transactions: [
    "id", "walletId", "toWalletId", "categoryId", "type", "amount", "note", "date", "photos", "createdAt", "updatedAt",
  ],
  budgets: ["id", "categoryId", "amount", "month", "year", "createdAt", "updatedAt"],
  subscriptions: [
    "id", "name", "amount", "currency", "cycle", "nextBilling", "categoryId", "walletId",
    "color", "icon", "note", "active", "createdAt", "updatedAt",
  ],
  planned: ["id", "type", "amount", "note", "categoryId", "walletId", "date", "done", "createdAt", "updatedAt"],
  prayers: [
    "id", "date", "prayer", "status", "qobliyah", "badiyah", "rakaat", "prayedAt", "note", "createdAt", "updatedAt",
  ],
  health: ["id", "date", "weight", "systolic", "diastolic", "pulse", "note", "createdAt", "updatedAt"],
  food: ["id", "date", "name", "meal", "calories", "photoUrl", "note", "createdAt", "updatedAt"],
  taskAreas: ["id", "name", "code", "color", "icon", "schedule", "sortOrder", "archived", "createdAt", "updatedAt"],
  tasks: [
    "id", "areaId", "title", "note", "bucket", "dueDate", "dueTime", "remindBefore", "recurrence", "seriesId",
    "done", "doneAt", "sortOrder", "amount", "walletId", "categoryId", "transactionId", "createdAt", "updatedAt",
  ],
  noteLabels: ["id", "name", "color", "pinnedTab", "sortOrder", "createdAt", "updatedAt"],
  notes: [
    "id", "title", "body", "checklist", "labels", "color", "pinned", "archived", "photos", "audio", "links", "source",
    "linkedTaskId", "linkedContentId", "linkedTransactionId", "createdAt", "updatedAt",
  ],
  socialAccounts: [
    "id", "platform", "platformName", "handle", "color", "targetPerWeek", "archived", "sortOrder", "createdAt", "updatedAt",
  ],
  contentPillars: ["id", "name", "color", "sortOrder", "createdAt", "updatedAt"],
  contentItems: [
    "id", "title", "stage", "format", "pillar", "idea", "noteId", "checklist", "photos", "assetLinks", "sponsor",
    "createdAt", "updatedAt",
  ],
  contentPosts: [
    "id", "contentId", "accountId", "caption", "hashtags", "scheduledAt", "remindBefore", "status", "postedAt", "url",
    "metrics", "metricsAt", "createdAt", "updatedAt",
  ],
  habits: [
    "id", "name", "emoji", "color", "kind", "schedule", "target", "reminders", "private", "why", "startDate",
    "archived", "sortOrder", "createdAt", "updatedAt",
  ],
  habitLogs: ["id", "habitId", "date", "type", "value", "note", "triggers", "at", "createdAt", "updatedAt"],
  assets: [
    "id", "kind", "symbol", "name", "currency", "priceMode", "manualPrice", "manualPriceAt", "unit", "walletId",
    "archived", "sortOrder", "createdAt", "updatedAt",
  ],
  assetTrades: [
    "id", "assetId", "type", "date", "quantity", "price", "fee", "amount", "ratio", "note", "cashTransactionId",
    "createdAt", "updatedAt",
  ],
};

/** Columns stored as JSON text that travel as JSON values on the wire. */
const JSON_FIELDS: Partial<Record<SyncEntity, Record<string, (raw: unknown) => unknown>>> = {
  transactions: { photos: (raw) => parsePhotos(raw as string | null) },
  taskAreas: { schedule: parseSchedule },
  tasks: { recurrence: parseRecurrence },
  notes: {
    checklist: parseChecklist,
    labels: parseLabelIds,
    photos: parseImageList,
    audio: parseAudio,
    links: parseLinks,
  },
  contentItems: {
    checklist: parseChecklist,
    photos: parseImageList,
    assetLinks: parseAssetLinks,
    sponsor: parseSponsor,
  },
  contentPosts: { metrics: parseMetrics },
  habits: { schedule: parseHabitSchedule, target: parseHabitTarget, reminders: parseReminders },
  habitLogs: { triggers: parseTriggers },
};

/** Pick the wire fields of a row; Dates become ISO strings, missing values null. */
export function serializeRow(entity: SyncEntity, row: object): Record<string, unknown> {
  const src = row as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  const json = JSON_FIELDS[entity];
  for (const f of ENTITY_FIELDS[entity]) {
    const v = src[f];
    const decode = json?.[f];
    out[f] = decode ? decode(v) : v instanceof Date ? v.toISOString() : (v ?? null);
  }
  return out;
}

export function serializeUser(u: User) {
  return { id: u.id, name: u.name, email: u.email, image: u.image, currency: u.currency, syncEpoch: u.syncEpoch };
}
