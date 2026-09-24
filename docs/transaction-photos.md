# Transaction photos — spec (web + mobile)

Every transaction type (expense, income, transfer, adjustment) can carry **up to 5
photos** — receipts, transfer proofs, invoices.

## Model

`Transaction.photos String @default("[]")` — JSON array of relative upload URLs
(`/uploads/<name>.<ext>`, same format the food log uses), in display order. On the wire
(`transactions` entity) it is a JSON **array of strings**, `[]` when none. Old app
versions that don't send it keep the stored value on update and get `[]` on create.

- Upload: existing `POST /api/mobile/upload` (image/*, ≤ 5 MB) → `{url}`; the web uses
  `saveUpload` from `src/lib/uploads.ts`. Clients compress before upload (max 1600 px
  wide, JPEG quality ~80).
- Server validation: ≤ 5 items (duplicates dropped), each matching
  `^/uploads/[A-Za-z0-9-]+\.[a-z]+$` — the exact shape `saveUpload` produces
  (`/uploads/<uuid>.<ext>`). (The earlier draft pattern `[A-Za-z0-9._-]+` also matched
  `/uploads/..`, a path-traversal risk for file deletion.) An upsert without `photos`
  keeps the stored list; `null` = `[]`.
- File cleanup: when a transaction's photos change, files removed from the list are
  deleted; deleting a transaction (any path, incl. cascades and reset) deletes its files
  — extend the existing tombstone/delete helpers, best effort. Files are removed only
  after the DB change commits and only if no other transaction/food row references the
  same URL (`deleteUnreferencedUploads` in `src/lib/uploads.ts`).
- Web: `createTransaction`/`updateTransaction` FormData fields `photos` (File, repeatable,
  ≤ 5 MB each) and, on update, `photosManaged=1` + `keepPhotos` (repeatable, existing URLs
  to keep, in order). Without `photosManaged` an update keeps all stored photos. Kept
  first, then new files; > 5 total throws. Server Action body limit is 26 MB.
- Mobile offline: photos taken offline are stored locally and listed with a local
  marker; the sync engine uploads each pending file before pushing the transaction
  upsert, then rewrites the list with the returned URLs (generalize the existing food
  photo flow). Display resolves relative URLs with the API base URL; local files show
  immediately.

## UI

- Forms (web + mobile): a "Foto" row with thumbnails, add (mobile: camera or gallery,
  multi-select from gallery; web: file input, multiple, drag & drop), remove, reorder is
  optional. Mobile quick-add keeps the keypad fast: photos are a chip in the
  wallet/date/note chip row, not a mandatory step.
- Lists: a small photo/paperclip badge with count on rows that have photos.
- Detail/edit: thumbnail strip; tap → full-screen viewer (swipe between photos, pinch
  zoom on mobile).
