import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../task_format.dart';
import '../widgets/recurrence_builder.dart';
import '../widgets/time_picker.dart';

/// `/tasks/areas/new` and `/tasks/areas/:id`.
class TaskAreaFormPage extends ConsumerWidget {
  const TaskAreaFormPage({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return const _AreaForm(existing: null);
    final area = ref.watch(watchTaskAreaProvider(id));
    Scaffold frame(Widget body) => Scaffold(
      appBar: AppBar(title: const Text('Ubah area')),
      body: body,
    );
    return area.when(
      skipLoadingOnReload: true,
      loading: () => frame(const LoadingListView(tiles: 3)),
      error: (_, _) => frame(
        ErrorRetry(onRetry: () => ref.invalidate(watchTaskAreaProvider(id))),
      ),
      data: (a) => a == null
          ? frame(
              EmptyState(
                mood: MascotMood.thinking,
                title: 'Area nggak ketemu',
                message: 'Mungkin sudah dihapus.',
                actionLabel: 'Kembali',
                onAction: () => popOr(context, '/tasks/areas'),
              ),
            )
          : _AreaForm(key: ValueKey(a.id), existing: a),
    );
  }
}

/// Uppercase A–Z/0–9, max 8, as you type.
class AreaCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = sanitizeAreaCode(newValue.text);
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

/// Validates the area form locally (same rules as the use case). Returns
/// field → message.
Map<String, String> validateAreaForm({
  required String name,
  required String code,
  required bool scheduled,
  required Set<int> days,
  required String start,
  required String end,
}) => {
  if (name.trim().isEmpty) 'name': 'Kasih nama areanya dulu, ya',
  if (name.trim().length > areaNameMax) 'name': 'Maksimal $areaNameMax huruf',
  if (!areaCodeRe.hasMatch(code)) 'code': 'Kode 1–8 huruf/angka (A–Z, 0–9)',
  if (scheduled && days.isEmpty) 'schedule': 'Pilih minimal satu hari',
  if (scheduled && days.isNotEmpty && start.compareTo(end) >= 0)
    'schedule': 'Jam mulai harus sebelum jam selesai',
};

class _AreaForm extends ConsumerStatefulWidget {
  const _AreaForm({super.key, required this.existing});
  final TaskArea? existing;

  @override
  ConsumerState<_AreaForm> createState() => _AreaFormState();
}

class _AreaFormState extends ConsumerState<_AreaForm> {
  TaskArea? get e => widget.existing;
  bool get _isEdit => e != null;

  late final _name = TextEditingController(text: e?.name ?? '');
  late final _code = TextEditingController(text: e?.code ?? '');
  late bool _codeTouched = _isEdit;
  late String _color = e?.color ?? '#1cb0f6';
  late String _icon = e?.icon ?? defaultAreaIcon;
  late bool _scheduled = e?.schedule != null;
  late Set<int> _days = {...(e?.schedule?.days ?? AreaSchedule.workHours.days)};
  late String _start = e?.schedule?.start ?? AreaSchedule.workHours.start;
  late String _end = e?.schedule?.end ?? AreaSchedule.workHours.end;
  final _errors = <String, String>{};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _code.text;
    setState(() {
      _errors
        ..clear()
        ..addAll(
          validateAreaForm(
            name: _name.text,
            code: code,
            scheduled: _scheduled,
            days: _days,
            start: _start,
            end: _end,
          ),
        );
    });
    if (_errors.isNotEmpty) return;
    setState(() => _saving = true);
    final input = TaskAreaInput(
      name: _name.text.trim(),
      code: code,
      color: _color,
      icon: _icon,
      schedule: _scheduled
          ? AreaSchedule(days: _days.toList()..sort(), start: _start, end: _end)
          : null,
    );
    final r = _isEdit
        ? await ref.read(updateTaskAreaProvider)(e!.id, input)
        : await ref.read(createTaskAreaProvider)(input);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (r) {
      case Ok(:final value):
        showToastBadge(
          context,
          message: _isEdit ? 'Area diperbarui 👍' : 'Area ${value.name} siap!',
          icon: Icons.category_rounded,
          color: CategoryColors.swatch(value.color),
        );
        popOr(context, '/tasks/areas');
      case Err(:final failure):
        if (failure is ValidationFailure && failure.field != null) {
          setState(() => _errors[failure.field!] = failure.message);
        } else {
          showFailureToast(context, failure);
        }
    }
  }

  Future<void> _pickTime(bool start) async {
    final v = await showChunkyTimePicker(
      context,
      initial: start ? _start : _end,
      title: start ? 'Jam mulai' : 'Jam selesai',
    );
    if (v == null || !mounted) return;
    setState(() {
      if (start) {
        _start = v;
      } else {
        _end = v;
      }
      _errors.remove('schedule');
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = CategoryColors.swatch(_color);
    final code = _code.text;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Ubah area' : 'Area baru')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ChunkyButton(
          key: const ValueKey('area-save'),
          label: 'Simpan',
          loading: _saving,
          onPressed: _save,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Live preview: the notification this area's tasks will show.
          ChunkyCard(
            key: const ValueKey('area-preview'),
            tinted: sw,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CategoryAvatar(iconName: _icon, colorHex: _color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notificationPreview(
                          code,
                          TaskBucket.fire,
                          'Contoh tugas',
                        ),
                        key: const ValueKey('area-preview-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.body
                            .w(900)
                            .copyWith(color: g.textPrimary),
                      ),
                      Text(
                        'Hari ini 14.00 · ${_name.text.trim().isEmpty ? 'Nama area' : _name.text.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GhinaType.bodyS.copyWith(color: g.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ChunkyTextField(
            key: const ValueKey('area-name'),
            label: 'Nama',
            hint: 'mis. Kuliah',
            controller: _name,
            errorText: _errors['name'],
            maxLength: areaNameMax,
            textInputAction: TextInputAction.next,
            onChanged: (v) => setState(() {
              _errors.remove('name');
              if (!_codeTouched) _code.text = suggestAreaCode(v);
            }),
          ),
          const SizedBox(height: 10),
          ChunkyTextField(
            key: const ValueKey('area-code'),
            label: 'Kode',
            hint: 'mis. KULIAH',
            controller: _code,
            errorText: _errors['code'],
            helperText: 'Maks 8 huruf/angka',
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [AreaCodeFormatter()],
            onChanged: (_) => setState(() {
              _codeTouched = true;
              _errors.remove('code');
            }),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Warna'),
          ChunkyColorPicker(
            selected: _color,
            size: 40,
            onChanged: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Ikon'),
          IconGridPicker(
            selected: _icon,
            icons: categoryIcons,
            color: CategoryColors.parse(_color),
            onChanged: (i) => setState(() => _icon = i),
          ),
          const SizedBox(height: 18),
          FieldLabel('Jadwal fokus', error: _errors.containsKey('schedule')),
          ChunkySegmented<bool>(
            segments: const [
              ChunkySegment(
                value: false,
                label: 'Tanpa jadwal',
                color: GhinaColors.gray,
              ),
              ChunkySegment(
                value: true,
                label: 'Terjadwal',
                color: GhinaColors.purple,
              ),
            ],
            value: _scheduled,
            onChanged: (v) => setState(() {
              _scheduled = v;
              _errors.remove('schedule');
            }),
          ),
          const SizedBox(height: 6),
          Text(
            _scheduled
                ? 'Selama jam ini, tab Tugas otomatis fokus ke area ini.'
                : 'Muncul di mode Fokus kalau nggak ada area terjadwal yang aktif.',
            style: GhinaType.caption.copyWith(color: g.textSecondary),
          ),
          if (_scheduled) ...[
            const SizedBox(height: 12),
            Shake(
              trigger: _errors['schedule'],
              child: DayToggleRow(
                keyPrefix: 'area-day',
                selected: _days,
                onChanged: (d) => setState(() {
                  _days = d;
                  _errors.remove('schedule');
                }),
              ),
            ),
            if (_errors['schedule'] != null) ...[
              const SizedBox(height: 6),
              Text(
                _errors['schedule']!,
                key: const ValueKey('area-schedule-error'),
                style: GhinaType.caption.copyWith(color: GhinaColors.red.base),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PickerField(
                    key: const ValueKey('area-start'),
                    label: 'Mulai',
                    value: hmDisplay(_start),
                    trailingIcon: Icons.schedule_rounded,
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PickerField(
                    key: const ValueKey('area-end'),
                    label: 'Selesai',
                    value: hmDisplay(_end),
                    trailingIcon: Icons.schedule_rounded,
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              scheduleSummary(
                _days.isEmpty
                    ? null
                    : AreaSchedule(
                        days: _days.toList(),
                        start: _start,
                        end: _end,
                      ),
              ),
              style: GhinaType.bodyS.w(800).copyWith(color: g.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
