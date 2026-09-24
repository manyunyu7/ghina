/// Composition root, part 3: notes (`docs/notes.md`) and the content planner
/// (`docs/content.md`). See `lib/di/README.md` → "Notes & content API".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/entities.dart';
import '../domain/usecases/usecases.dart';
import 'core_providers.dart';
import 'usecase_providers.dart'
    show createTaskProvider, createTransactionProvider;

// ---------------------------------------------------------------- writes

/// `(NoteInput(...))` → [Note]. Blank notes → `ValidationFailure(field: 'empty')`.
final createNoteProvider = Provider<CreateNote>(
  (ref) =>
      CreateNote(ref.watch(noteRepositoryProvider), ref.watch(clockProvider)),
);

/// `(id, NoteInput)` → [Note] (editor save; `photos`/`audio` null = unchanged).
final updateNoteProvider = Provider<UpdateNote>(
  (ref) =>
      UpdateNote(ref.watch(noteRepositoryProvider), ref.watch(clockProvider)),
);

/// Real delete (confirm first); archive is the soft option.
final deleteNoteProvider = Provider<DeleteNote>(
  (ref) => DeleteNote(ref.watch(noteRepositoryProvider)),
);
final setNotePinnedProvider = Provider<SetNotePinned>(
  (ref) => SetNotePinned(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Archiving unpins.
final setNoteArchivedProvider = Provider<SetNoteArchived>(
  (ref) => SetNoteArchived(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, 'red' | … | null)` — palette ids of `noteColors`.
final setNoteColorProvider = Provider<SetNoteColor>(
  (ref) =>
      SetNoteColor(ref.watch(noteRepositoryProvider), ref.watch(clockProvider)),
);
final setNoteLabelsProvider = Provider<SetNoteLabels>(
  (ref) => SetNoteLabels(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final toggleNoteLabelProvider = Provider<ToggleNoteLabel>(
  (ref) => ToggleNoteLabel(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setNoteChecklistProvider = Provider<SetNoteChecklist>(
  (ref) => SetNoteChecklist(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final toggleNoteChecklistItemProvider = Provider<ToggleNoteChecklistItem>(
  (ref) => ToggleNoteChecklistItem(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final addNotePhotosProvider = Provider<AddNotePhotos>(
  (ref) => AddNotePhotos(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final removeNotePhotoProvider = Provider<RemoveNotePhoto>(
  (ref) => RemoveNotePhoto(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setNotePhotosProvider = Provider<SetNotePhotos>(
  (ref) => SetNotePhotos(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, NoteAudioInput(path:, durationSec:, transcript:))` — uploads on sync.
final addNoteAudioProvider = Provider<AddNoteAudio>(
  (ref) =>
      AddNoteAudio(ref.watch(noteRepositoryProvider), ref.watch(clockProvider)),
);
final removeNoteAudioProvider = Provider<RemoveNoteAudio>(
  (ref) => RemoveNoteAudio(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setNoteAudioTranscriptProvider = Provider<SetNoteAudioTranscript>(
  (ref) => SetNoteAudioTranscript(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(id, clip)` → appends the clip's transcript to the body.
final insertTranscriptIntoBodyProvider = Provider<InsertTranscriptIntoBody>(
  (ref) => InsertTranscriptIntoBody(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(noteId, txId?)` — link a transaction saved by the form.
final linkNoteTransactionProvider = Provider<LinkNoteTransaction>(
  (ref) => LinkNoteTransaction(
    ref.watch(noteRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final createNoteLabelProvider = Provider<CreateNoteLabel>(
  (ref) => CreateNoteLabel(
    ref.watch(noteLabelRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateNoteLabelProvider = Provider<UpdateNoteLabel>(
  (ref) => UpdateNoteLabel(
    ref.watch(noteLabelRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setNoteLabelPinnedTabProvider = Provider<SetNoteLabelPinnedTab>(
  (ref) => SetNoteLabelPinnedTab(
    ref.watch(noteLabelRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final reorderNoteLabelsProvider = Provider<ReorderNoteLabels>(
  (ref) => ReorderNoteLabels(
    ref.watch(noteLabelRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// Removes the label from every note too (confirm in the UI).
final deleteNoteLabelProvider = Provider<DeleteNoteLabel>(
  (ref) => DeleteNoteLabel(ref.watch(noteLabelRepositoryProvider)),
);

/// `(userId)` → 0/1. Offline fallback before the first notes-aware pull.
final seedDefaultNoteLabelProvider = Provider<SeedDefaultNoteLabel>(
  (ref) => SeedDefaultNoteLabel(
    ref.watch(noteLabelRepositoryProvider),
    ref.watch(defaultsSeedStateProvider),
    ref.watch(clockProvider),
  ),
);
final createSocialAccountProvider = Provider<CreateSocialAccount>(
  (ref) => CreateSocialAccount(
    ref.watch(socialAccountRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateSocialAccountProvider = Provider<UpdateSocialAccount>(
  (ref) => UpdateSocialAccount(
    ref.watch(socialAccountRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setSocialAccountArchivedProvider = Provider<SetSocialAccountArchived>(
  (ref) => SetSocialAccountArchived(
    ref.watch(socialAccountRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final reorderSocialAccountsProvider = Provider<ReorderSocialAccounts>(
  (ref) => ReorderSocialAccounts(
    ref.watch(socialAccountRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// Deletes the account **and its posts**.
final deleteSocialAccountProvider = Provider<DeleteSocialAccount>(
  (ref) => DeleteSocialAccount(ref.watch(socialAccountRepositoryProvider)),
);
final createContentPillarProvider = Provider<CreateContentPillar>(
  (ref) => CreateContentPillar(
    ref.watch(contentPillarRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateContentPillarProvider = Provider<UpdateContentPillar>(
  (ref) => UpdateContentPillar(
    ref.watch(contentPillarRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final reorderContentPillarsProvider = Provider<ReorderContentPillars>(
  (ref) => ReorderContentPillars(
    ref.watch(contentPillarRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final deleteContentPillarProvider = Provider<DeleteContentPillar>(
  (ref) => DeleteContentPillar(ref.watch(contentPillarRepositoryProvider)),
);

/// `(userId)` → 0/5. Offline fallback before the first content-aware pull.
final seedDefaultContentPillarsProvider = Provider<SeedDefaultContentPillars>(
  (ref) => SeedDefaultContentPillars(
    ref.watch(contentPillarRepositoryProvider),
    ref.watch(defaultsSeedStateProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final createContentItemProvider = Provider<CreateContentItem>(
  (ref) => CreateContentItem(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final updateContentItemProvider = Provider<UpdateContentItem>(
  (ref) => UpdateContentItem(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// Deletes the item **and its posts**; the source note stays.
final deleteContentItemProvider = Provider<DeleteContentItem>(
  (ref) => DeleteContentItem(ref.watch(contentItemRepositoryProvider)),
);
final moveContentStageProvider = Provider<MoveContentStage>(
  (ref) => MoveContentStage(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setContentChecklistProvider = Provider<SetContentChecklist>(
  (ref) => SetContentChecklist(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final toggleContentChecklistItemProvider = Provider<ToggleContentChecklistItem>(
  (ref) => ToggleContentChecklistItem(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final addContentPhotosProvider = Provider<AddContentPhotos>(
  (ref) => AddContentPhotos(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final removeContentPhotoProvider = Provider<RemoveContentPhoto>(
  (ref) => RemoveContentPhoto(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setContentPhotosProvider = Provider<SetContentPhotos>(
  (ref) => SetContentPhotos(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setContentSponsorProvider = Provider<SetContentSponsor>(
  (ref) => SetContentSponsor(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final markSponsorUnpaidProvider = Provider<MarkSponsorUnpaid>(
  (ref) => MarkSponsorUnpaid(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(clockProvider),
  ),
);

/// `(itemId, record: SponsorPayment(walletId:, …)?)` → `(item, transaction)`.
final markSponsorPaidProvider = Provider<MarkSponsorPaid>(
  (ref) => MarkSponsorPaid(
    ref.watch(contentItemRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(createTransactionProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(contentId, ContentPostInput(accountId:, …))` → post; auto-advances the stage.
final createContentPostProvider = Provider<CreateContentPost>(
  (ref) => CreateContentPost(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(contentItemRepositoryProvider),
    ref.watch(socialAccountRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final updateContentPostProvider = Provider<UpdateContentPost>(
  (ref) => UpdateContentPost(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(contentItemRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final scheduleContentPostProvider = Provider<ScheduleContentPost>(
  (ref) => ScheduleContentPost(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(contentItemRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// "Sudah tayang": `(id, postedAt:, url:)`; auto-advances the stage.
final markPostPostedProvider = Provider<MarkPostPosted>(
  (ref) => MarkPostPosted(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(contentItemRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final markPostSkippedProvider = Provider<MarkPostSkipped>(
  (ref) => MarkPostSkipped(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(contentItemRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);
final reopenContentPostProvider = Provider<ReopenContentPost>(
  (ref) => ReopenContentPost(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final setPostMetricsProvider = Provider<SetPostMetrics>(
  (ref) => SetPostMetrics(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(clockProvider),
  ),
);
final deleteContentPostProvider = Provider<DeleteContentPost>(
  (ref) => DeleteContentPost(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(contentItemRepositoryProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(noteId, NoteTaskInput(areaId:, bucket:, …))` → `(note, task)`.
final convertNoteToTaskProvider = Provider<ConvertNoteToTask>(
  (ref) => ConvertNoteToTask(
    ref.watch(noteRepositoryProvider),
    ref.watch(createTaskProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(noteId, format:, pillar:, title:)` → `(note, item)` (idempotent).
final convertNoteToContentProvider = Provider<ConvertNoteToContent>(
  (ref) => ConvertNoteToContent(
    ref.watch(noteRepositoryProvider),
    ref.watch(contentItemRepositoryProvider),
    ref.watch(createContentItemProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(noteId, TransactionInput)` → `(note, transaction)`; prefill with `noteTransactionDraft(note)`.
final convertNoteToTransactionProvider = Provider<ConvertNoteToTransaction>(
  (ref) => ConvertNoteToTransaction(
    ref.watch(noteRepositoryProvider),
    ref.watch(createTransactionProvider),
    ref.watch(unitOfWorkProvider),
    ref.watch(clockProvider),
  ),
);

/// `(SharedNoteInput(text:, subject:, imagePaths:))` → [Note] (`source = share`).
final createNoteFromShareProvider = Provider<CreateNoteFromShare>(
  (ref) => CreateNoteFromShare(ref.watch(createNoteProvider)),
);

// ---------------------------------------------------------------- reads (notes)

/// Notes for a filter (`NoteFilter.all`, `NoteFilter.archive`,
/// `NoteFilter.label(id)`, `NoteFilter(search: 'kopi', archived: null)`):
/// pinned first, then most recently updated.
final watchNotesProvider = StreamProvider.autoDispose
    .family<List<NoteView>, NoteFilter>(
      (ref, f) => WatchNotes(
        ref.watch(noteRepositoryProvider),
        ref.watch(noteLabelRepositoryProvider),
      )(f),
    );

/// One note with its labels (editor); null when deleted.
final watchNoteProvider = StreamProvider.autoDispose.family<NoteView?, String>(
  (ref, id) => WatchNote(
    ref.watch(noteRepositoryProvider),
    ref.watch(noteLabelRepositoryProvider),
  )(id),
);

/// Every label in order (label manager, label picker).
final watchNoteLabelsProvider = StreamProvider.autoDispose<List<NoteLabel>>(
  (ref) => WatchNoteLabels(ref.watch(noteLabelRepositoryProvider))(),
);

/// Labels pinned as tabs, in order (the "Semua" tab is the UI's own).
final watchNoteTabsProvider = StreamProvider.autoDispose<List<NoteLabel>>(
  (ref) =>
      WatchNoteLabels(ref.watch(noteLabelRepositoryProvider))(pinnedOnly: true),
);

/// Idea inbox: "Ide Konten" notes not converted yet.
final watchIdeaInboxProvider = StreamProvider.autoDispose<List<Note>>(
  (ref) => WatchIdeaInbox(
    ref.watch(noteRepositoryProvider),
    ref.watch(noteLabelRepositoryProvider),
  )(),
);

// ---------------------------------------------------------------- reads (content)

/// Non-archived accounts in order (pickers, filters).
final watchSocialAccountsProvider =
    StreamProvider.autoDispose<List<SocialAccount>>(
      (ref) =>
          WatchSocialAccounts(ref.watch(socialAccountRepositoryProvider))(),
    );

/// Every account incl. archived (account manager).
final watchAllSocialAccountsProvider =
    StreamProvider.autoDispose<List<SocialAccount>>(
      (ref) => WatchSocialAccounts(ref.watch(socialAccountRepositoryProvider))(
        includeArchived: true,
      ),
    );

final watchContentPillarsProvider =
    StreamProvider.autoDispose<List<ContentPillar>>(
      (ref) =>
          WatchContentPillars(ref.watch(contentPillarRepositoryProvider))(),
    );

/// The pipeline board (6 columns) for a filter.
final watchContentBoardProvider = StreamProvider.autoDispose
    .family<ContentBoard, ContentFilter>(
      (ref, f) => WatchContentBoard(
        ref.watch(contentItemRepositoryProvider),
        ref.watch(contentPostRepositoryProvider),
        ref.watch(socialAccountRepositoryProvider),
      )(f),
    );

/// One item with its posts and source note; null when deleted.
final watchContentItemProvider = StreamProvider.autoDispose
    .family<ContentItemView?, String>(
      (ref, id) => WatchContentItem(
        ref.watch(contentItemRepositoryProvider),
        ref.watch(contentPostRepositoryProvider),
        ref.watch(socialAccountRepositoryProvider),
        ref.watch(noteRepositoryProvider),
      )(id),
    );

/// One post with account + item (the reminder tap target `/content/posts/<id>`).
final watchContentPostProvider = StreamProvider.autoDispose
    .family<ContentPostView?, String>(
      (ref, id) => WatchContentPost(
        ref.watch(contentPostRepositoryProvider),
        ref.watch(contentItemRepositoryProvider),
        ref.watch(socialAccountRepositoryProvider),
      )(id),
    );

/// Calendar of local days: `weekRange(day)` or `monthGridRange(YearMonth(y, m))`.
final watchContentCalendarProvider = StreamProvider.autoDispose
    .family<ContentCalendar, ({DateTime from, DateTime to})>(
      (ref, r) => WatchContentCalendar(
        ref.watch(contentPostRepositoryProvider),
        ref.watch(contentItemRepositoryProvider),
        ref.watch(socialAccountRepositoryProvider),
      )(r.from, r.to),
    );

/// Home card "Tayang hari ini" (hide when `isEmpty`).
final watchTodayPostsProvider = StreamProvider.autoDispose<TodayPosts>(
  (ref) => WatchTodayPosts(
    ref.watch(contentPostRepositoryProvider),
    ref.watch(contentItemRepositoryProvider),
    ref.watch(socialAccountRepositoryProvider),
    ref.watch(tickSourceProvider),
  )(),
);

/// Posted posts waiting for "Isi performa?" (≥ 3 days, no metrics).
final watchMetricsDueProvider =
    StreamProvider.autoDispose<List<ContentPostView>>(
      (ref) => WatchMetricsDue(
        ref.watch(contentPostRepositoryProvider),
        ref.watch(contentItemRepositoryProvider),
        ref.watch(socialAccountRepositoryProvider),
        ref.watch(tickSourceProvider),
      )(),
    );

/// Report for a local day range (inclusive) + sponsor summary.
final watchContentReportProvider = StreamProvider.autoDispose
    .family<ContentReport, ({DateTime from, DateTime to})>(
      (ref, r) => WatchContentReport(
        ref.watch(contentItemRepositoryProvider),
        ref.watch(contentPostRepositoryProvider),
        ref.watch(socialAccountRepositoryProvider),
        ref.watch(transactionRepositoryProvider),
        ref.watch(tickSourceProvider),
      )(r.from, r.to),
    );
