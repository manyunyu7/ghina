import '../../../domain/entities/entities.dart';

/// Pre-filled values handed from the quick-add sheet to `/tasks/new`
/// (GoRouter `extra`).
final class TaskDraft {
  const TaskDraft({
    this.title = '',
    this.bucket,
    this.areaId,
    this.dueDate,
    this.dueTime,
  });

  final String title;
  final TaskBucket? bucket;
  final String? areaId;
  final DateTime? dueDate;
  final String? dueTime;
}
