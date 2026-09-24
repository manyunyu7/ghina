/// The chunky "edit prayer" sheet (status, rawatib, time, note) and the shared
/// write actions used by the prayers page and the report's color map.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/game/game.dart' show XpRules;
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/rewards/rewards.dart';
import '../../../shared/widgets/widgets.dart';
import 'prayer_visuals.dart';

/// Writes + reward moments for prayers. Every method is safe to call after the
/// widget is gone (checks `context.mounted`).
abstract final class PrayerActions {
  /// Quick log (tap on an empty tile): status jamaah. [dayEntries] = the day's
  /// rows before the write (for the "all five" celebration).
  static Future<bool> quickLog(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    Prayer prayer,
    Map<Prayer, PrayerEntry> dayEntries,
  ) async {
    final rewards = RewardTracker.start(ref);
    final r = await ref.read(setPrayerStatusProvider)(
      day,
      prayer,
      PrayerStatus.quick,
    );
    if (!context.mounted) return false;
    switch (r) {
      case Ok(:final value):
        HapticFeedback.mediumImpact();
        await _afterSave(context, ref, rewards, day, dayEntries, value);
        return true;
      case Err(:final failure):
        showFailureToast(context, failure);
        return false;
    }
  }

  /// Opens the edit sheet for a fardhu and applies the result.
  static Future<void> edit(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    Prayer prayer,
    Map<Prayer, PrayerEntry> dayEntries,
  ) async {
    final entry = dayEntries[prayer];
    final res = await showChunkyBottomSheet<_SheetResult>(
      context,
      title: prayer.label,
      showClose: true,
      builder: (c) => PrayerEditSheet(day: day, prayer: prayer, entry: entry),
    );
    if (res == null || !context.mounted) return;
    switch (res) {
      case _Clear():
        final r = await ref.read(clearPrayerProvider)(day, prayer);
        if (!context.mounted) return;
        switch (r) {
          case Ok():
            HapticFeedback.selectionClick();
            showOkToast(
              context,
              '${prayer.label} dikosongkan',
              icon: Icons.undo_rounded,
            );
          case Err(:final failure):
            showFailureToast(context, failure);
        }
      case _Save(:final input):
        final rewards = RewardTracker.start(ref);
        final r = await ref.read(savePrayerDetailsProvider)(day, prayer, input);
        if (!context.mounted) return;
        switch (r) {
          case Ok(:final value):
            HapticFeedback.mediumImpact();
            await _afterSave(context, ref, rewards, day, dayEntries, value);
          case Err(:final failure):
            showFailureToast(context, failure);
        }
    }
  }

  /// Marks a daily sunnah done / not done, or changes its rakaat. The reward
  /// moment only plays when it becomes done ([reward]).
  static Future<void> setSunnah(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    Prayer prayer, {
    required bool done,
    int? rakaat,
    bool reward = true,
  }) async {
    final rewards = done && reward ? RewardTracker.start(ref) : null;
    final r = await ref.read(setSunnahProvider)(
      day,
      prayer,
      done: done,
      rakaat: rakaat,
    );
    if (!context.mounted) return;
    switch (r) {
      case Ok():
        if (rewards == null) {
          HapticFeedback.selectionClick();
        } else {
          HapticFeedback.lightImpact();
          await rewards.finish(context);
        }
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  static Future<void> _afterSave(
    BuildContext context,
    WidgetRef ref,
    RewardTracker rewards,
    DateTime day,
    Map<Prayer, PrayerEntry> before,
    PrayerEntry saved,
  ) async {
    int prayed(Map<Prayer, PrayerEntry> m) =>
        Prayer.fardhu.where((p) => m[p]?.status.isPrayed ?? false).length;
    final after = {...before, saved.prayer: saved};
    final nowAll = prayed(before) < 5 && prayed(after) == 5;
    if (nowAll) {
      final today = startOfDay(ref.read(clockProvider).now());
      await showCelebration(
        context,
        title: 'Lima waktu lengkap! 🕌',
        subtitle: isSameDay(day, today)
            ? 'Semua salat hari ini sudah dikerjakan. MasyaAllah, keren!'
            : 'Semua salat ${Fmt.dateLong(day)} sudah dikerjakan.',
        stats: const [
          CelebrationStat(
            label: 'Bonus',
            value: '+${XpRules.allPrayersBonus} XP',
            icon: Icons.bolt_rounded,
            color: GhinaColors.yellow,
          ),
        ],
      );
    }
    if (context.mounted) await rewards.finish(context);
  }
}

sealed class _SheetResult {
  const _SheetResult();
}

final class _Save extends _SheetResult {
  const _Save(this.input);
  final PrayerDetailsInput input;
}

final class _Clear extends _SheetResult {
  const _Clear();
}

/// Pick any of the 7 statuses, rawatib (only where they exist), optional time
/// and note. Pops a `_SheetResult`.
class PrayerEditSheet extends StatefulWidget {
  const PrayerEditSheet({
    super.key,
    required this.day,
    required this.prayer,
    this.entry,
  });

  final DateTime day;
  final Prayer prayer;
  final PrayerEntry? entry;

  @override
  State<PrayerEditSheet> createState() => _PrayerEditSheetState();
}

class _PrayerEditSheetState extends State<PrayerEditSheet> {
  late PrayerStatus _status;
  late bool _qobliyah;
  late bool _badiyah;
  TimeOfDay? _time;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _status = e?.status ?? PrayerStatus.quick;
    _qobliyah = e?.qobliyah ?? false;
    _badiyah = e?.badiyah ?? false;
    final at = e?.prayedAt;
    _time = at == null ? null : TimeOfDay(hour: at.hour, minute: at.minute);
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _xp =>
      prayerStatusXp(_status) +
      (_status.isPrayed
          ? ((_qobliyah ? 1 : 0) + (_badiyah ? 1 : 0)) * XpRules.rawatib
          : 0);

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
      helpText: 'Jam salat',
      cancelText: 'Batal',
      confirmText: 'Pilih',
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null && mounted) setState(() => _time = t);
  }

  void _save() {
    final t = _time;
    final d = widget.day;
    Navigator.of(context).pop(
      _Save(
        PrayerDetailsInput(
          status: _status,
          qobliyah: _qobliyah,
          badiyah: _badiyah,
          prayedAt: t == null
              ? null
              : DateTime(d.year, d.month, d.day, t.hour, t.minute),
          note: _note.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final p = widget.prayer;
    final prayed = _status.isPrayed;
    final statuses = PrayerStatus.fardhu;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Transform.translate(
          offset: const Offset(0, -10),
          child: Text(
            Fmt.dateFull(widget.day),
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'STATUS',
                style: GhinaType.overline.copyWith(color: g.textSecondary),
              ),
            ),
            if (_xp > 0)
              Pulse(
                trigger: _xp,
                child: XpBadge(
                  key: const ValueKey('sheet-xp'),
                  xp: _xp,
                  plus: true,
                ),
              ),
          ],
        ),
        const SizedBox(height: GhinaSpace.sm),
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - GhinaSpace.sm) / 2;
            return Wrap(
              spacing: GhinaSpace.sm,
              runSpacing: GhinaSpace.sm,
              children: [
                for (final s in statuses)
                  SizedBox(
                    width: s == PrayerStatus.excused ? c.maxWidth : w,
                    child: _StatusOption(
                      key: ValueKey('status-${s.wire}'),
                      status: s,
                      selected: s == _status,
                      onTap: () => setState(() => _status = s),
                    ),
                  ),
              ],
            );
          },
        ),
        if (p.rawatibSlots > 0) ...[
          const SizedBox(height: GhinaSpace.lg),
          Text(
            'RAWATIB',
            style: GhinaType.overline.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: GhinaSpace.sm),
          Opacity(
            opacity: prayed ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !prayed,
              child: ChunkyChoiceChips<RawatibSlot>(
                multi: true,
                allowEmpty: true,
                options: [
                  for (final slot in RawatibSlot.values)
                    if (slot.allowedFor(p))
                      ChunkyChoice(
                        value: slot,
                        label: '${slot.label} +${XpRules.rawatib}',
                        icon: slot == RawatibSlot.qobliyah
                            ? Icons.first_page_rounded
                            : Icons.last_page_rounded,
                        color: GhinaColors.green,
                      ),
                ],
                selected: {
                  if (prayed && _qobliyah) RawatibSlot.qobliyah,
                  if (prayed && _badiyah) RawatibSlot.badiyah,
                },
                onChanged: (s) => setState(() {
                  _qobliyah = s.contains(RawatibSlot.qobliyah);
                  _badiyah = s.contains(RawatibSlot.badiyah);
                }),
              ),
            ),
          ),
          if (!prayed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Rawatib bisa dicentang kalau salatnya dikerjakan.',
                style: GhinaType.caption.copyWith(color: g.textMuted),
              ),
            ),
        ],
        const SizedBox(height: GhinaSpace.lg),
        Row(
          children: [
            Expanded(
              child: PickerField(
                key: const ValueKey('prayer-time'),
                label: 'Jam salat (opsional)',
                leading: const Icon(Icons.schedule_rounded, size: 20),
                value: _time == null
                    ? null
                    : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
                placeholder: 'Pilih jam',
                onTap: _pickTime,
              ),
            ),
            if (_time != null) ...[
              const SizedBox(width: GhinaSpace.sm),
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: ChunkyIconButton(
                  icon: Icons.close_rounded,
                  size: 40,
                  tooltip: 'Hapus jam',
                  onPressed: () => setState(() => _time = null),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: GhinaSpace.md),
        ChunkyTextField(
          key: const ValueKey('prayer-note'),
          controller: _note,
          label: 'Catatan (opsional)',
          hint: 'Contoh: di masjid kantor',
          maxLength: prayerNoteMax,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: GhinaSpace.lg),
        ChunkyButton(
          key: const ValueKey('prayer-save'),
          label: 'Simpan',
          size: ChunkyButtonSize.large,
          color: prayerStatusSwatch(_status),
          onPressed: _save,
        ),
        if (widget.entry != null) ...[
          const SizedBox(height: GhinaSpace.sm),
          ChunkyButton(
            key: const ValueKey('prayer-clear'),
            label: 'Kosongkan',
            icon: Icons.undo_rounded,
            variant: ChunkyButtonVariant.ghost,
            color: GhinaColors.red,
            onPressed: () => Navigator.of(context).pop(const _Clear()),
          ),
        ],
      ],
    );
  }
}

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    super.key,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final PrayerStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = prayerStatusSwatch(status);
    final fg = selected ? sw.on : g.textPrimary;
    final pts = status.points;
    return ChunkySurface(
      color: selected ? sw.base : g.surface,
      edgeColor: selected ? sw.edge : g.borderEdge,
      borderColor: selected ? null : g.border,
      depth: GhinaDepth.sm,
      borderRadius: GhinaRadii.rLg,
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      onTap: onTap,
      semanticLabel: status.label,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: selected ? sw.on.withValues(alpha: 0.22) : sw.base,
              shape: BoxShape.circle,
            ),
            child: Icon(prayerStatusIcon(status), size: 18, color: sw.on),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS
                      .w(800)
                      .copyWith(color: fg, height: 1.15),
                ),
                Text(
                  pts == null
                      ? 'Tidak dihitung'
                      : (pts == 0 ? '0 XP' : '+$pts XP'),
                  maxLines: 1,
                  style: GhinaType.caption.copyWith(
                    color: selected
                        ? sw.on.withValues(alpha: 0.85)
                        : g.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
