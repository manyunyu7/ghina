import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../state/notifications/notification_providers.dart';
import '../task_draft.dart';
import '../task_format.dart';
import 'reminder_settings.dart';
import 'task_visuals.dart';
import 'time_picker.dart';

/// Fast add: title (autofocus) + bucket + optional due → Simpan. "Lengkap"
/// opens the full form with what's typed so far.
Future<void> showQuickAddTask(
  BuildContext context, {
  TaskBucket bucket = TaskBucket.want,
  String? areaId,
}) => showChunkyBottomSheet<void>(
  context,
  title: 'Tugas baru',
  showClose: true,
  builder: (_) => QuickAddTaskForm(
    pageContext: context,
    initialBucket: bucket,
    initialAreaId: areaId,
  ),
);

enum _Due { none, today, tomorrow, custom }

class QuickAddTaskForm extends ConsumerStatefulWidget {
  const QuickAddTaskForm({
    super.key,
    required this.pageContext,
    this.initialBucket = TaskBucket.want,
    this.initialAreaId,
  });

  /// Outlives the sheet (toasts, navigation).
  final BuildContext pageContext;
  final TaskBucket initialBucket;
  final String? initialAreaId;

  @override
  ConsumerState<QuickAddTaskForm> createState() => _QuickAddTaskFormState();
}

class _QuickAddTaskFormState extends ConsumerState<QuickAddTaskForm> {
  final _title = TextEditingController();
  late TaskBucket _bucket = widget.initialBucket;
  late String? _areaId = widget.initialAreaId;
  _Due _due = _Due.none;
  DateTime? _customDay;
  String? _time;
  String? _error;
  bool _saving = false;

  DateTime get _today => startOfDay(ref.read(clockProvider).now());

  DateTime? get _dueDay => switch (_due) {
    _Due.none => null,
    _Due.today => _today,
    _Due.tomorrow => addDays(_today, 1),
    _Due.custom => _customDay,
  };

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final d = await showGhinaDatePicker(
      context,
      initial: _customDay ?? _dueDay ?? _today,
      title: 'Tanggal',
      today: _today,
    );
    if (d == null || !mounted) return;
    setState(() {
      _customDay = startOfDay(d);
      _due = _Due.custom;
    });
  }

  Future<void> _pickTime() async {
    final t = await showChunkyTimePicker(context, initial: _time);
    if (t != null && mounted) setState(() => _time = t);
  }

  String? _resolveAreaId(List<TaskArea> areas) {
    if (_areaId != null && areas.any((a) => a.id == _areaId)) return _areaId;
    final focus = ref.read(watchFocusAreasProvider).value;
    return focus?.areas.firstOrNull?.id ?? areas.firstOrNull?.id;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Tulis tugasnya dulu, ya');
      return;
    }
    final areas = ref.read(watchTaskAreasProvider).value ?? const <TaskArea>[];
    final areaId = _resolveAreaId(areas);
    if (areaId == null) {
      setState(() => _error = 'Belum ada area. Bikin area dulu, ya');
      return;
    }
    final day = _dueDay;
    final time = day == null ? null : _time;
    final settings = ref.read(notificationSettingsProvider).value;
    final remind = time != null && (settings?.enabled ?? true)
        ? (settings?.defaultRemindBefore ?? 10)
        : null;
    setState(() => _saving = true);
    if (remind != null) await ensureReminderPermission(context, ref);
    if (!mounted) return;
    final r = await ref.read(createTaskProvider)(
      TaskInput(
        areaId: areaId,
        title: title,
        bucket: _bucket,
        dueDate: day,
        dueTime: time,
        remindBefore: remind,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok(:final value):
        final page = widget.pageContext;
        Navigator.of(context).pop();
        if (page.mounted) {
          showToastBadge(
            page,
            message: '${value.bucket.emoji} Tugas ditambah!',
            icon: Icons.add_task_rounded,
            color: bucketSwatch(value.bucket),
          );
        }
      case Err(:final failure):
        setState(
          () =>
              _error = failure is ValidationFailure && failure.field == 'title'
              ? failure.message
              : null,
        );
        if (_error == null) showFailureToast(context, failure);
    }
  }

  void _openFull() {
    final draft = TaskDraft(
      title: _title.text.trim(),
      bucket: _bucket,
      areaId: _resolveAreaId(
        ref.read(watchTaskAreasProvider).value ?? const [],
      ),
      dueDate: _dueDay,
      dueTime: _dueDay == null ? null : _time,
    );
    final page = widget.pageContext;
    Navigator.of(context).pop();
    if (page.mounted) page.push('/tasks/new', extra: draft);
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final areas = ref.watch(watchTaskAreasProvider).value ?? const <TaskArea>[];
    ref.watch(watchFocusAreasProvider);
    ref.watch(notificationSettingsProvider);
    final areaId = _resolveAreaId(areas);
    final now = ref.read(clockProvider).now();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          key: const ValueKey('quick-title'),
          hint: 'Mau ngerjain apa?',
          controller: _title,
          autofocus: true,
          errorText: _error,
          inputFormatters: [LengthLimitingTextInputFormatter(taskTitleMax)],
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        ChunkySegmented<TaskBucket>(
          segments: bucketSegments(),
          value: _bucket,
          onChanged: (b) => setState(() => _bucket = b),
        ),
        const SizedBox(height: 6),
        Text(
          '${_bucket.display}: ${_bucket.meaning}',
          style: GhinaType.caption.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChunkyChip(
              label: 'Hari ini',
              icon: Icons.today_rounded,
              selected: _due == _Due.today,
              color: GhinaColors.orange,
              onTap: () => setState(
                () => _due = _due == _Due.today ? _Due.none : _Due.today,
              ),
            ),
            ChunkyChip(
              label: 'Besok',
              icon: Icons.wb_sunny_rounded,
              selected: _due == _Due.tomorrow,
              color: GhinaColors.orange,
              onTap: () => setState(
                () => _due = _due == _Due.tomorrow ? _Due.none : _Due.tomorrow,
              ),
            ),
            ChunkyChip(
              label: _due == _Due.custom && _customDay != null
                  ? dayLabel(_customDay!, now)
                  : 'Pilih tanggal',
              icon: Icons.event_rounded,
              selected: _due == _Due.custom,
              color: GhinaColors.orange,
              onTap: _pickDay,
            ),
            if (_dueDay != null)
              ChunkyChip(
                key: const ValueKey('quick-time'),
                label: _time == null ? '+ Jam' : hmDisplay(_time!),
                icon: Icons.schedule_rounded,
                selected: _time != null,
                color: GhinaColors.blue,
                onTap: _pickTime,
              ),
          ],
        ),
        if (areas.length > 1) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final a in areas)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChunkyChip(
                      label: a.name,
                      icon: GhinaIcons.of(a.icon),
                      color: areaSwatch(a),
                      selected: a.id == areaId,
                      onTap: () => setState(() => _areaId = a.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('quick-full'),
                label: 'Lengkap',
                variant: ChunkyButtonVariant.outline,
                color: GhinaColors.blue,
                icon: Icons.tune_rounded,
                onPressed: _openFull,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChunkyButton(
                key: const ValueKey('quick-save'),
                label: 'Simpan',
                loading: _saving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
