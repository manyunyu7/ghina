import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/rewards/rewards.dart';
import 'health_page.dart' show bpSwatch, formatKg;

enum _Mode { weight, bp, both }

/// Log or edit a health entry. `/health/new?mode=bp` opens on blood pressure
/// (like the web's two "Log weight" / "Log blood pressure" buttons).
class HealthFormPage extends ConsumerStatefulWidget {
  const HealthFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  ConsumerState<HealthFormPage> createState() => _HealthFormPageState();
}

class _HealthFormPageState extends ConsumerState<HealthFormPage> {
  final _weight = TextEditingController();
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _pulse = TextEditingController();
  final _note = TextEditingController();
  final _dateText = TextEditingController();

  DateTime? _date;
  _Mode _mode = _Mode.weight;
  bool _modeFromRoute = false;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.id != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_modeFromRoute || _isEdit) return;
    _modeFromRoute = true;
    try {
      final m = GoRouterState.of(context).uri.queryParameters['mode'];
      if (m == 'bp') _mode = _Mode.bp;
      if (m == 'both') _mode = _Mode.both;
    } catch (_) {
      // Not under a GoRouter (tests): keep the default.
    }
  }

  @override
  void dispose() {
    for (final c in [_weight, _sys, _dia, _pulse, _note, _dateText]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _dateOrNow => _date ?? ref.read(clockProvider).now();

  void _setDate(DateTime d) {
    _date = d;
    _dateText.text = Fmt.dateFull(d);
  }

  void _fill(HealthEntry e) {
    if (_loaded) return;
    _loaded = true;
    if (e.weight != null) _weight.text = formatKg(e.weight!);
    if (e.systolic != null) _sys.text = '${e.systolic}';
    if (e.diastolic != null) _dia.text = '${e.diastolic}';
    if (e.pulse != null) _pulse.text = '${e.pulse}';
    _note.text = e.note ?? '';
    _setDate(e.date);
    final hasW = e.weight != null;
    final hasBp = e.systolic != null || e.pulse != null;
    _mode = hasW && hasBp ? _Mode.both : (hasBp ? _Mode.bp : _Mode.weight);
  }

  double? _parseDouble(String s) {
    final t = s.trim().replaceAll(' ', '').replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  int? _parseInt(String s) {
    final t = s.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  bool get _wantsWeight => _mode != _Mode.bp;
  bool get _wantsBp => _mode != _Mode.weight;

  Map<String, String> _validate() {
    final e = <String, String>{};
    if (_wantsWeight) {
      final w = _parseDouble(_weight.text);
      if (_weight.text.trim().isEmpty) {
        e['weight'] = 'Isi berat badanmu dulu ya';
      } else if (w == null || w < 1 || w > 500) {
        e['weight'] = 'Berat badan sepertinya salah (1–500 kg)';
      }
    }
    if (_wantsBp) {
      final s = _parseInt(_sys.text), d = _parseInt(_dia.text);
      if (_sys.text.trim().isEmpty) {
        e['systolic'] = 'Isi sistolik (angka atas)';
      } else if (s == null || s < 50 || s > 300) {
        e['systolic'] = 'Sistolik 50–300';
      }
      if (_dia.text.trim().isEmpty) {
        e['diastolic'] = 'Isi diastolik (angka bawah)';
      } else if (d == null || d < 30 || d > 200) {
        e['diastolic'] = 'Diastolik 30–200';
      }
      if (_pulse.text.trim().isNotEmpty) {
        final p = _parseInt(_pulse.text);
        if (p == null || p < 20 || p > 250) e['pulse'] = 'Denyut nadi 20–250';
      }
    }
    return e;
  }

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider).now();
    final cur = _dateOrNow;
    final picked = await showGhinaDatePicker(
      context,
      initial: cur.isAfter(now) ? now : cur,
      title: 'Tanggal pengukuran',
      firstDate: DateTime(2000),
      lastDate: now,
      today: now,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _setDate(
        DateTime(picked.year, picked.month, picked.day, cur.hour, cur.minute),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    final input = HealthInput(
      date: _dateOrNow,
      weight: _wantsWeight ? _parseDouble(_weight.text) : null,
      systolic: _wantsBp ? _parseInt(_sys.text) : null,
      diastolic: _wantsBp ? _parseInt(_dia.text) : null,
      pulse: _wantsBp ? _parseInt(_pulse.text) : null,
      note: _note.text,
    );
    setState(() => _saving = true);
    final rewards = RewardTracker.start(ref);
    final r = _isEdit
        ? await ref.read(updateHealthEntryProvider)(widget.id!, input)
        : await ref.read(createHealthEntryProvider)(input);
    if (!mounted) return;
    switch (r) {
      case Ok():
        if (_isEdit) {
          showToastBadge(
            context,
            message: 'Perubahan tersimpan 👍',
            icon: Icons.check_circle_rounded,
            color: GhinaColors.green,
          );
        } else {
          await rewards.finish(
            context,
            xpToast: (xp) => 'Tercatat! +$xp XP',
            doneToast: 'Tercatat 👍',
          );
        }
        if (mounted) context.pop();
      case Err(:final failure):
        setState(() {
          _saving = false;
          if (failure case ValidationFailure(:final field?)) {
            _errors = {..._errors, field: failure.message};
          }
        });
        showErrorToast(context, failure.message);
    }
  }

  Future<void> _delete() async {
    final ok = await showChunkyConfirm(
      context,
      title: 'Hapus catatan ini?',
      message: 'Catatan kesehatan ini akan dihapus permanen.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteHealthEntryProvider)(widget.id!);
    if (!mounted) return;
    switch (r) {
      case Ok():
        showToastBadge(
          context,
          message: 'Catatan dihapus',
          icon: Icons.delete_rounded,
          color: GhinaColors.gray,
        );
        context.pop();
      case Err(:final failure):
        showErrorToast(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    Widget body;
    if (_isEdit) {
      final async = ref.watch(watchHealthEntryProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _fill(value);
          body = _form();
        case AsyncData():
          body = EmptyState(
            title: 'Catatan nggak ketemu',
            message: 'Mungkin sudah dihapus di perangkat lain.',
            mood: MascotMood.thinking,
            actionLabel: 'Kembali',
            onAction: () => context.pop(),
          );
        case AsyncError():
          body = ErrorRetry(
            onRetry: () => ref.invalidate(watchHealthEntryProvider(widget.id!)),
          );
        default:
          body = const Padding(
            padding: EdgeInsets.all(GhinaSpace.page),
            child: SkeletonList(count: 4),
          );
      }
    } else {
      if (_date == null) _setDate(ref.read(clockProvider).now());
      body = _form();
    }
    final showSave = !_isEdit || _loaded;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah catatan' : 'Catat kesehatan'),
        actions: [
          if (_isEdit && _loaded)
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: showSave
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                GhinaSpace.page,
                8,
                GhinaSpace.page,
                12 +
                    MediaQuery.paddingOf(context).bottom +
                    MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ChunkyButton(
                label: _isEdit ? 'Simpan perubahan' : 'Simpan',
                loading: _saving,
                onPressed: _save,
              ),
            )
          : null,
    );
  }

  Widget _unit(String text) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: Center(
      widthFactor: 1,
      child: Text(
        text,
        style: GhinaType.body
            .w(800)
            .copyWith(color: context.ghina.textSecondary),
      ),
    ),
  );

  Widget _form() {
    final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))];
    final cat = _wantsBp
        ? classifyBp(_parseInt(_sys.text), _parseInt(_dia.text))
        : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        24,
      ),
      children: [
        MascotSpeech(
          mood: MascotMood.thinking,
          mascotSize: 64,
          message: switch (_mode) {
            _Mode.weight =>
              'Timbang di jam yang sama tiap hari biar hasilnya konsisten.',
            _Mode.bp => 'Duduk tenang 5 menit dulu sebelum mengukur tensi, ya.',
            _Mode.both => 'Mantap, sekalian catat berat dan tensi!',
          },
        ),
        const SizedBox(height: 16),
        ChunkySegmented<_Mode>(
          value: _mode,
          onChanged: (m) => setState(() {
            _mode = m;
            _errors = const {};
          }),
          segments: const [
            ChunkySegment(
              value: _Mode.weight,
              label: 'Berat',
              icon: Icons.monitor_weight_rounded,
              color: GhinaColors.green,
            ),
            ChunkySegment(
              value: _Mode.bp,
              label: 'Tensi',
              icon: Icons.favorite_rounded,
              color: GhinaColors.red,
            ),
            ChunkySegment(
              value: _Mode.both,
              label: 'Keduanya',
              color: GhinaColors.purple,
            ),
          ],
        ),
        const SizedBox(height: 20),
        ChunkyTextField(
          label: 'Tanggal',
          controller: _dateText,
          readOnly: true,
          prefixIcon: Icons.event_rounded,
          onTap: _pickDate,
        ),
        if (_wantsWeight) ...[
          const SizedBox(height: 16),
          ChunkyTextField(
            key: const ValueKey('weight'),
            label: 'Berat badan',
            hint: 'mis. 68,5',
            controller: _weight,
            prefixIcon: Icons.monitor_weight_rounded,
            suffix: _unit('kg'),
            errorText: _errors['weight'],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            textInputAction: TextInputAction.next,
          ),
        ],
        if (_wantsBp) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ChunkyTextField(
                  key: const ValueKey('systolic'),
                  label: 'Sistolik',
                  hint: '120',
                  controller: _sys,
                  errorText: _errors['systolic'],
                  keyboardType: TextInputType.number,
                  inputFormatters: numFmt,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 40, 8, 0),
                child: Text(
                  '/',
                  style: GhinaType.h1.copyWith(color: context.ghina.textMuted),
                ),
              ),
              Expanded(
                child: ChunkyTextField(
                  key: const ValueKey('diastolic'),
                  label: 'Diastolik',
                  hint: '80',
                  controller: _dia,
                  errorText: _errors['diastolic'],
                  keyboardType: TextInputType.number,
                  inputFormatters: numFmt,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (cat != null) ...[
            const SizedBox(height: 10),
            PopIn(
              key: ValueKey(cat.level),
              child: ChunkyCard(
                tinted: bpSwatch(cat),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(Icons.favorite_rounded, color: Color(cat.color)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Kategori: ${cat.label}',
                        style: GhinaType.body.w(800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ChunkyTextField(
            key: const ValueKey('pulse'),
            label: 'Denyut nadi (opsional)',
            hint: 'mis. 72',
            controller: _pulse,
            prefixIcon: Icons.monitor_heart_rounded,
            suffix: _unit('bpm'),
            errorText: _errors['pulse'],
            keyboardType: TextInputType.number,
            inputFormatters: numFmt,
            textInputAction: TextInputAction.next,
          ),
        ],
        const SizedBox(height: 16),
        ChunkyTextField(
          key: const ValueKey('note'),
          label: 'Catatan (opsional)',
          hint: 'mis. habis olahraga',
          controller: _note,
          prefixIcon: Icons.sticky_note_2_rounded,
          maxLength: 200,
        ),
        if (_isEdit) ...[
          const SizedBox(height: 8),
          ChunkyButton(
            label: 'Hapus catatan',
            icon: Icons.delete_outline_rounded,
            variant: ChunkyButtonVariant.ghost,
            color: GhinaColors.red,
            onPressed: _delete,
          ),
        ],
      ],
    );
  }
}
