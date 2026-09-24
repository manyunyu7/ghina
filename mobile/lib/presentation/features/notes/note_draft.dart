import '../../../domain/entities/entities.dart';

/// What a new note starts with — pass as `extra` to `/notes/new`
/// (e.g. the label of the tab the user was on).
final class NoteDraft {
  const NoteDraft({
    this.labelIds = const [],
    this.source = NoteSource.quick,
    this.checklist = false,
  });

  final List<String> labelIds;
  final NoteSource source;

  /// Start with an empty checklist row instead of the body.
  final bool checklist;
}
