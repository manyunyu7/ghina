import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/failure.dart';
import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/rewards/rewards.dart';
import '../widgets/food_photo.dart';

/// Log or edit a meal: photo (camera/gallery, compressed), name, meal type,
/// calories, date and note.
class FoodFormPage extends ConsumerStatefulWidget {
  const FoodFormPage({super.key, this.id});

  /// Null when creating a new item.
  final String? id;

  @override
  ConsumerState<FoodFormPage> createState() => _FoodFormPageState();
}

class _FoodFormPageState extends ConsumerState<FoodFormPage> {
  final _name = TextEditingController();
  final _calories = TextEditingController();
  final _note = TextEditingController();
  final _dateText = TextEditingController();

  DateTime? _date;
  MealType? _meal;
  FoodLog? _existing;
  String? _pickedPath;
  bool _removePhoto = false;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.id != null;

  @override
  void dispose() {
    for (final c in [_name, _calories, _note, _dateText]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _dateOrNow => _date ?? ref.read(clockProvider).now();

  void _setDate(DateTime d) {
    _date = d;
    _dateText.text = Fmt.dateFull(d);
  }

  static MealType _guessMeal(DateTime t) => t.hour < 10
      ? MealType.breakfast
      : t.hour < 15
      ? MealType.lunch
      : t.hour < 18
      ? MealType.snack
      : MealType.dinner;

  void _fill(FoodLog l) {
    if (_loaded) return;
    _loaded = true;
    _existing = l;
    _name.text = l.name;
    _calories.text = l.calories?.toString() ?? '';
    _note.text = l.note ?? '';
    _meal = l.meal;
    _setDate(l.date);
  }

  bool get _hasPhoto =>
      _pickedPath != null || (!_removePhoto && (_existing?.hasPhoto ?? false));

  Future<void> _pickPhoto() async {
    final source = await showChunkyBottomSheet<ImageSource>(
      context,
      title: 'Tambah foto',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChunkyTile(
            leading: const CategoryAvatar(
              icon: Icons.photo_camera_rounded,
              color: Color(0xFFFF9600),
              size: 40,
            ),
            title: 'Kamera',
            subtitle: 'Foto langsung makananmu',
            onTap: () => Navigator.of(c).pop(ImageSource.camera),
          ),
          const SizedBox(height: 10),
          ChunkyTile(
            leading: const CategoryAvatar(
              icon: Icons.photo_library_rounded,
              color: Color(0xFF1CB0F6),
              size: 40,
            ),
            title: 'Galeri',
            subtitle: 'Pilih dari foto yang ada',
            onTap: () => Navigator.of(c).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    try {
      // Compressed on pick: the server accepts up to 5 MB.
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (x == null || !mounted) return;
      setState(() {
        _pickedPath = x.path;
        _removePhoto = false;
      });
    } on PlatformException catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        source == ImageSource.camera
            ? 'Nggak bisa buka kamera. Cek izin kamera di pengaturan HP, ya.'
            : 'Nggak bisa buka galeri. Cek izin foto di pengaturan HP, ya.',
      );
    }
  }

  void _clearPhoto() => setState(() {
    _pickedPath = null;
    _removePhoto = true;
  });

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider).now();
    final cur = _dateOrNow;
    final picked = await showGhinaDatePicker(
      context,
      initial: cur.isAfter(now) ? now : cur,
      title: 'Tanggal makan',
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

  Map<String, String> _validate() {
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) e['name'] = 'Isi nama makanannya dulu ya';
    final c = _calories.text.trim();
    if (c.isNotEmpty) {
      final v = int.tryParse(c);
      if (v == null || v < 0 || v > 20000) {
        e['calories'] = 'Kalori sepertinya salah (0–20.000)';
      }
    }
    return e;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    final input = FoodInput(
      date: _dateOrNow,
      name: _name.text,
      meal: _meal,
      calories: int.tryParse(_calories.text.trim()),
      note: _note.text,
    );
    setState(() => _saving = true);
    final rewards = RewardTracker.start(ref);
    final r = _isEdit
        ? await ref.read(updateFoodLogProvider)(
            widget.id!,
            input,
            photoPath: _pickedPath,
            removePhoto: _removePhoto && _pickedPath == null,
          )
        : await ref.read(createFoodLogProvider)(input, photoPath: _pickedPath);
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
            xpToast: (xp) => 'Nyam! +$xp XP',
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
      title: 'Hapus catatan makan?',
      message:
          '"${_name.text.trim()}" akan dihapus permanen, termasuk fotonya.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final r = await ref.read(deleteFoodLogProvider)(widget.id!);
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
      final async = ref.watch(watchFoodLogProvider(widget.id!));
      switch (async) {
        case AsyncData(:final value?):
          _fill(value);
          // Keep the photo state fresh (e.g. uploaded while open).
          _existing = value;
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
            onRetry: () => ref.invalidate(watchFoodLogProvider(widget.id!)),
          );
        default:
          body = const Padding(
            padding: EdgeInsets.all(GhinaSpace.page),
            child: SkeletonList(count: 4),
          );
      }
    } else {
      if (_date == null) {
        final now = ref.read(clockProvider).now();
        _setDate(now);
        _meal = _guessMeal(now);
      }
      body = _form();
    }
    final showSave = !_isEdit || _loaded;
    return Scaffold(
      backgroundColor: g.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Ubah catatan makan' : 'Catat makanan'),
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
                color: GhinaColors.orange,
                onPressed: _save,
              ),
            )
          : null,
    );
  }

  Widget _photo() {
    final g = context.ghina;
    if (!_hasPhoto) {
      return Semantics(
        button: true,
        label: 'Tambah foto',
        child: ChunkySurface(
          color: g.surfaceAlt,
          edgeColor: g.border,
          borderColor: g.border,
          depth: GhinaDepth.md,
          borderRadius: GhinaRadii.rXl,
          onTap: _pickPhoto,
          child: SizedBox(
            height: 140,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_a_photo_rounded,
                  size: 36,
                  color: GhinaColors.orange.base,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tambah foto',
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                Text(
                  'Opsional, tapi bikin diary-mu lebih seru',
                  style: GhinaType.caption.copyWith(color: g.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final Widget image = _pickedPath != null
            ? ClipRRect(
                borderRadius: GhinaRadii.rXl,
                child: Image.file(
                  File(_pickedPath!),
                  width: w,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => MealEmojiTile(
                    meal: _meal,
                    width: w,
                    height: 200,
                    radius: GhinaRadii.rXl,
                  ),
                ),
              )
            : FoodPhoto(
                log: _existing!,
                width: w,
                height: 200,
                radius: GhinaRadii.rXl,
              );
        return Stack(
          children: [
            image,
            Positioned(
              top: 10,
              right: 10,
              child: ChunkyIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Hapus foto',
                size: 40,
                onPressed: _clearPhoto,
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: ChunkyButton(
                label: 'Ganti foto',
                icon: Icons.photo_camera_rounded,
                size: ChunkyButtonSize.small,
                variant: ChunkyButtonVariant.outline,
                onPressed: _pickPhoto,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        24,
      ),
      children: [
        _photo(),
        const SizedBox(height: 20),
        ChunkyTextField(
          key: const ValueKey('name'),
          label: 'Makan apa?',
          hint: 'mis. Nasi goreng + telur',
          controller: _name,
          prefixIcon: Icons.restaurant_rounded,
          errorText: _errors['name'],
          maxLength: 120,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        Text('Waktu makan', style: GhinaType.h3),
        const SizedBox(height: 8),
        ChunkyChoiceChips<MealType>(
          options: [
            for (final m in MealType.values)
              ChunkyChoice(
                value: m,
                label: '${m.emoji} ${m.label}',
                color: mealSwatch(m),
              ),
          ],
          selected: {?_meal},
          allowEmpty: true,
          onChanged: (s) => setState(() => _meal = s.isEmpty ? null : s.first),
        ),
        const SizedBox(height: 18),
        ChunkyTextField(
          key: const ValueKey('calories'),
          label: 'Kalori (opsional)',
          hint: 'mis. 450',
          controller: _calories,
          prefixIcon: Icons.local_fire_department_rounded,
          suffix: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                'kkal',
                style: GhinaType.body
                    .w(800)
                    .copyWith(color: context.ghina.textSecondary),
              ),
            ),
          ),
          errorText: _errors['calories'],
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        ChunkyTextField(
          label: 'Tanggal',
          controller: _dateText,
          readOnly: true,
          prefixIcon: Icons.event_rounded,
          onTap: _pickDate,
        ),
        const SizedBox(height: 16),
        ChunkyTextField(
          key: const ValueKey('note'),
          label: 'Catatan (opsional)',
          hint: 'mis. kepedesan, kenyang banget',
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
