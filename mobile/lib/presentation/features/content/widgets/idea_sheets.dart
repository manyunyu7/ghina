import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import 'content_visuals.dart';

/// Format + pillar chips (single choice, tap again to clear).
class FormatPillarPicker extends StatelessWidget {
  const FormatPillarPicker({
    super.key,
    required this.format,
    required this.pillar,
    required this.pillars,
    required this.onFormat,
    required this.onPillar,
  });

  final ContentFormat? format;
  final String? pillar;
  final List<ContentPillar> pillars;
  final ValueChanged<ContentFormat?> onFormat;
  final ValueChanged<String?> onPillar;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const FieldLabel('Format'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in ContentFormat.values)
            ChunkyChip(
              key: ValueKey('format-${f.wire}'),
              label: f.label,
              icon: formatIcon(f),
              selected: format == f,
              color: GhinaColors.purple,
              onTap: () => onFormat(format == f ? null : f),
            ),
        ],
      ),
      if (pillars.isNotEmpty || pillar != null) ...[
        const SizedBox(height: 16),
        const FieldLabel('Pilar'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in pillars)
              ChunkyChip(
                key: ValueKey('pillar-${p.name}'),
                label: p.name,
                selected: pillar?.toLowerCase() == p.name.toLowerCase(),
                color: readableSwatch(context, p.color),
                onTap: () => onPillar(
                  pillar?.toLowerCase() == p.name.toLowerCase() ? null : p.name,
                ),
              ),
            if (pillar != null &&
                !pillars.any(
                  (p) => p.name.toLowerCase() == pillar!.toLowerCase(),
                ))
              ChunkyChip(
                label: pillar!,
                selected: true,
                onTap: () => onPillar(null),
              ),
          ],
        ),
      ],
    ],
  );
}

/// Quick add: title (+ format/pillar) → a new item at [stage]. Returns the
/// new item, or null.
Future<ContentItem?> showQuickAddIdeaSheet(
  BuildContext context, {
  ContentStage stage = ContentStage.ide,
}) => showChunkyBottomSheet<ContentItem>(
  context,
  title: stage == ContentStage.ide
      ? 'Ide baru 💡'
      : 'Konten baru di ${stage.label}',
  showClose: true,
  builder: (_) => _QuickAddIdea(stage: stage),
);

class _QuickAddIdea extends ConsumerStatefulWidget {
  const _QuickAddIdea({required this.stage});
  final ContentStage stage;

  @override
  ConsumerState<_QuickAddIdea> createState() => _QuickAddIdeaState();
}

class _QuickAddIdeaState extends ConsumerState<_QuickAddIdea> {
  final _title = TextEditingController();
  ContentFormat? _format;
  String? _pillar;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await ref.read(createContentItemProvider)(
      ContentItemInput(
        title: _title.text,
        stage: widget.stage,
        format: _format,
        pillar: _pillar,
      ),
    );
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pillars = ref.watch(watchContentPillarsProvider).value ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyTextField(
          key: const ValueKey('quick-idea-title'),
          controller: _title,
          label: 'Judul',
          hint: 'Mis. 5 tips hemat ngopi',
          autofocus: true,
          maxLength: contentTitleMax,
          errorText: _error,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        FormatPillarPicker(
          format: _format,
          pillar: _pillar,
          pillars: pillars,
          onFormat: (f) => setState(() => _format = f),
          onPillar: (p) => setState(() => _pillar = p),
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          key: const ValueKey('quick-idea-save'),
          label: 'Simpan ide',
          icon: Icons.lightbulb_rounded,
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// "Jadikan konten": pick format/pillar for an inbox note. Returns
/// `(format, pillar)` or null when dismissed.
Future<({ContentFormat? format, String? pillar})?> showConvertIdeaSheet(
  BuildContext context, {
  required String title,
}) => showChunkyBottomSheet<({ContentFormat? format, String? pillar})>(
  context,
  title: 'Jadikan konten',
  showClose: true,
  builder: (_) => _ConvertIdea(title: title),
);

class _ConvertIdea extends ConsumerStatefulWidget {
  const _ConvertIdea({required this.title});
  final String title;

  @override
  ConsumerState<_ConvertIdea> createState() => _ConvertIdeaState();
}

class _ConvertIdeaState extends ConsumerState<_ConvertIdea> {
  ContentFormat? _format;
  String? _pillar;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final pillars = ref.watch(watchContentPillarsProvider).value ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GhinaType.h3.copyWith(color: g.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Masuk ke papan di tahap 💡 Ide. Isi, checklist dan fotonya ikut.',
          style: GhinaType.bodyS.copyWith(color: g.textSecondary),
        ),
        const SizedBox(height: 16),
        FormatPillarPicker(
          format: _format,
          pillar: _pillar,
          pillars: pillars,
          onFormat: (f) => setState(() => _format = f),
          onPillar: (p) => setState(() => _pillar = p),
        ),
        const SizedBox(height: 20),
        ChunkyButton(
          key: const ValueKey('convert-idea-save'),
          label: 'Jadikan konten',
          icon: Icons.auto_awesome_rounded,
          onPressed: () =>
              Navigator.of(context).pop((format: _format, pillar: _pillar)),
        ),
      ],
    );
  }
}
