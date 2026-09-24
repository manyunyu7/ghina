import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatters.dart';
import '../../../../core/result.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../content_actions.dart';
import '../content_format.dart';
import '../widgets/content_visuals.dart';
import '../widgets/time_picker.dart';

/// One post (an item on one account) — also where reminder taps land:
/// caption + hashtags, schedule, reminder, "Salin caption", "Buka
/// Instagram", "Sudah tayang" and the performance form.
class ContentPostPage extends ConsumerStatefulWidget {
  const ContentPostPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ContentPostPage> createState() => _ContentPostPageState();
}

class _ContentPostPageState extends ConsumerState<ContentPostPage> {
  final _caption = TextEditingController();
  final _hashtags = TextEditingController();
  DateTime? _at;
  int? _remind;
  ContentPost? _base;
  bool _saving = false;

  final _metric = {for (final k in _metricKeys) k.$1: TextEditingController()};
  PostMetrics? _metricsBase;

  static const _metricKeys = [
    ('views', 'Views', Icons.visibility_rounded),
    ('likes', 'Likes', Icons.favorite_rounded),
    ('comments', 'Komentar', Icons.chat_bubble_rounded),
    ('shares', 'Share', Icons.send_rounded),
    ('saves', 'Simpan', Icons.bookmark_rounded),
    ('followers', 'Followers baru', Icons.person_add_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _caption.addListener(_changed);
    _hashtags.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _caption.dispose();
    _hashtags.dispose();
    for (final c in _metric.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty {
    final b = _base;
    if (b == null) return false;
    return _caption.text != b.caption ||
        _hashtags.text != b.hashtags ||
        _at != b.scheduledAt ||
        _remindOf(_at, _remind) != _remindOf(b.scheduledAt, b.remindBefore);
  }

  /// The reminder that is saved: none without a date (see [_input]), so
  /// "Hapus jadwal" + Simpan leaves the form clean.
  static int? _remindOf(DateTime? at, int? remind) =>
      at == null ? null : remind;

  void _sync(ContentPost p) {
    if (_base == null || (!_dirty && _base != p)) {
      _caption.text = p.caption;
      _hashtags.text = p.hashtags;
      _at = p.scheduledAt;
      _remind = p.remindBefore;
      _base = p;
    }
    if (_metricsBase != p.metrics) {
      final m = p.metrics;
      final values = {
        'views': m.views,
        'likes': m.likes,
        'comments': m.comments,
        'shares': m.shares,
        'saves': m.saves,
        'followers': m.followers,
      };
      for (final e in values.entries) {
        _metric[e.key]!.text = e.value == null ? '' : '${e.value}';
      }
      _metricsBase = m;
    }
  }

  List<ContentPost> _siblings(ContentPostView v) {
    final item = ref.read(watchContentItemProvider(v.post.contentId)).value;
    return [for (final p in item?.posts ?? const <ContentPostView>[]) p.post];
  }

  ContentPostInput _input(ContentPostView v) => ContentPostInput(
    accountId: v.post.accountId,
    caption: _caption.text,
    hashtags: _hashtags.text,
    scheduledAt: _at,
    remindBefore: _at == null ? null : _remind,
    url: v.post.url,
  );

  Future<bool> _save(ContentPostView v, {bool quiet = false}) async {
    if (!_dirty) return true;
    if (_saving) return false;
    setState(() => _saving = true);
    final input = _input(v);
    final p = await postChangeFlow(
      context,
      ref,
      item: v.item,
      posts: _siblings(v),
      write: () => ref.read(updateContentPostProvider)(v.id, input),
      doneToast: quiet ? null : 'Tersimpan 👍',
    );
    if (!mounted) return p != null;
    setState(() {
      _saving = false;
      if (p != null) {
        _base = p;
        // Show what was stored (hashtags are trimmed, CRLF → LF…) unless
        // the user kept typing meanwhile — otherwise the form stays dirty.
        if (_caption.text == input.caption) _caption.text = p.caption;
        if (_hashtags.text == input.hashtags) _hashtags.text = p.hashtags;
      }
    });
    return p != null;
  }

  Future<void> _markPosted(ContentPostView v) async {
    final url = await showChunkyBottomSheet<String>(
      context,
      title: 'Sudah tayang? 🚀',
      showClose: true,
      builder: (_) => _PostedSheet(initialUrl: v.post.url),
    );
    if (url == null || !mounted) return;
    if (!await _save(v, quiet: true) || !mounted) return;
    await markPostedFlow(
      context,
      ref,
      view: v,
      siblings: _siblings(v),
      url: url,
    );
  }

  Future<void> _saveMetrics(ContentPostView v) async {
    int? n(String k) => parseCount(_metric[k]!.text);
    final r = await ref.read(setPostMetricsProvider)(
      v.id,
      PostMetrics(
        views: n('views'),
        likes: n('likes'),
        comments: n('comments'),
        shares: n('shares'),
        saves: n('saves'),
        followers: n('followers'),
      ),
    );
    if (!mounted) return;
    switch (r) {
      case Ok():
        FocusScope.of(context).unfocus();
        showOkToast(context, 'Performa tersimpan 📊');
      case Err(:final failure):
        showFailureToast(context, failure);
    }
  }

  Future<void> _menu(ContentPostView v, String action) async {
    switch (action) {
      case 'skip':
        await postChangeFlow(
          context,
          ref,
          item: v.item,
          posts: _siblings(v),
          write: () => ref.read(markPostSkippedProvider)(v.id),
          doneToast: 'Dilewati',
        );
      case 'reopen':
        final r = await ref.read(reopenContentPostProvider)(v.id);
        if (!mounted) return;
        switch (r) {
          case Ok():
            showOkToast(context, 'Dibuka lagi');
          case Err(:final failure):
            showFailureToast(context, failure);
        }
      case 'delete':
        final ok = await showChunkyConfirm(
          context,
          title: 'Hapus posting ini?',
          message:
              'Posting untuk ${v.account?.atHandle ?? 'akun ini'} dihapus. Kontennya tetap ada.',
          confirmLabel: 'Hapus',
          destructive: true,
        );
        if (!ok || !mounted) return;
        final r = await ref.read(deleteContentPostProvider)(v.id);
        if (!mounted) return;
        switch (r) {
          case Ok():
            showOkToast(context, 'Posting dihapus');
            popOr(context, '/content');
          case Err(:final failure):
            showFailureToast(context, failure);
        }
    }
  }

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider).now();
    final base = _at ?? DateTime(now.year, now.month, now.day, 19);
    final d = await showGhinaDatePicker(
      context,
      initial: base,
      title: 'Tanggal tayang',
      today: now,
    );
    if (d == null) return;
    setState(() {
      _at = DateTime(d.year, d.month, d.day, base.hour, base.minute);
      _remind ??= _base?.remindBefore ?? 30;
    });
  }

  Future<void> _pickTime() async {
    final now = ref.read(clockProvider).now();
    final base = _at ?? DateTime(now.year, now.month, now.day, 19);
    final hm = await showContentTimePicker(
      context,
      initial: formatHm(base.hour, base.minute),
      title: 'Jam tayang',
    );
    if (hm == null) return;
    setState(() {
      _at = DateTime(
        base.year,
        base.month,
        base.day,
        int.parse(hm.substring(0, 2)),
        int.parse(hm.substring(3, 5)),
      );
      _remind ??= _base?.remindBefore ?? 30;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(watchContentPostProvider(widget.id));
    final v = async.value;
    if (v != null) {
      _sync(v.post);
      // Keep the item's posts warm for auto-advance / siblings.
      ref.watch(watchContentItemProvider(v.post.contentId));
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || v == null) return;
        final keep = await showChunkyConfirm(
          this.context,
          title: 'Simpan perubahan?',
          message: 'Caption atau jadwal belum disimpan.',
          confirmLabel: 'Simpan',
          cancelLabel: 'Buang',
        );
        if (!mounted) return;
        if (keep) {
          if (!await _save(v) || !mounted) return;
        } else {
          _base = null;
          setState(() {});
          _sync(v.post);
        }
        if (mounted) popOr(this.context, '/content');
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Posting'),
          actions: [
            if (v != null)
              PopupMenuButton<String>(
                key: const ValueKey('post-overflow'),
                tooltip: 'Menu',
                onSelected: (a) => _menu(v, a),
                itemBuilder: (_) => [
                  if (v.post.isPosted || v.post.isSkipped)
                    const PopupMenuItem(
                      value: 'reopen',
                      child: Text('Buka lagi (belum tayang)'),
                    )
                  else
                    const PopupMenuItem(value: 'skip', child: Text('Lewati')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Hapus posting'),
                  ),
                ],
              ),
          ],
        ),
        bottomNavigationBar: v == null || !_dirty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GhinaSpace.page,
                    8,
                    GhinaSpace.page,
                    12,
                  ),
                  child: ChunkyButton(
                    key: const ValueKey('post-save'),
                    label: 'Simpan',
                    loading: _saving,
                    onPressed: () => _save(v),
                  ),
                ),
              ),
        body: async.when(
          skipLoadingOnReload: true,
          loading: () => const LoadingListView(),
          error: (_, _) => ErrorRetry(
            onRetry: () => ref.invalidate(watchContentPostProvider(widget.id)),
          ),
          data: (v) => v == null
              ? EmptyState(
                  mood: MascotMood.thinking,
                  title: 'Posting nggak ditemukan',
                  message: 'Mungkin sudah dihapus di perangkat lain.',
                  actionLabel: 'Ke papan konten',
                  onAction: () => context.go('/content'),
                )
              : _body(v),
        ),
      ),
    );
  }

  Widget _body(ContentPostView v) {
    final g = context.ghina;
    final p = v.post;
    final now = ref.read(clockProvider).now();
    final account = v.account;
    final copyText = ContentPost(
      id: '',
      contentId: '',
      accountId: '',
      caption: _caption.text,
      hashtags: _hashtags.text,
      createdAt: now,
      updatedAt: now,
    ).copyText;
    final canOpen = account != null && platformOpenUrls(account).isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        GhinaSpace.page,
        8,
        GhinaSpace.page,
        40,
      ),
      children: [
        _Header(view: v, now: now),
        const SizedBox(height: 16),
        if (needsMetricsPrompt(p, now)) ...[
          ChunkyCard(
            key: const ValueKey('post-metrics-prompt'),
            tinted: GhinaColors.purple,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.insights_rounded,
                  color: GhinaColors.purple.base,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Isi performa? Sudah ${daysSince(p.postedAt!, now)} hari sejak tayang — catat angkanya biar laporanmu makin tajam.',
                    style: GhinaType.bodyS
                        .w(700)
                        .copyWith(color: g.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Big actions.
        ChunkyButton(
          key: const ValueKey('post-copy'),
          label: 'Salin caption',
          icon: Icons.content_copy_rounded,
          variant: ChunkyButtonVariant.secondary,
          onPressed: () => copyCaption(context, copyText),
        ),
        if (canOpen) ...[
          const SizedBox(height: 10),
          ChunkyButton(
            key: const ValueKey('post-open'),
            label: 'Buka ${account.platformLabel}',
            icon: platformIcon(account.platform),
            color: readableSwatch(context, account.color),
            onPressed: () => openPlatform(context, ref, account),
          ),
        ],
        if (!p.isPosted) ...[
          const SizedBox(height: 10),
          ChunkyButton(
            key: const ValueKey('post-posted'),
            label: 'Sudah tayang',
            icon: Icons.rocket_launch_rounded,
            color: GhinaColors.green,
            onPressed: () => _markPosted(v),
          ),
        ] else if (p.url != null) ...[
          const SizedBox(height: 10),
          ChunkyButton(
            key: const ValueKey('post-live'),
            label: 'Lihat postingan',
            icon: Icons.open_in_new_rounded,
            variant: ChunkyButtonVariant.outline,
            onPressed: () => openUrlOrToast(context, ref, p.url!),
          ),
        ],
        if (p.isPosted) ...[const SizedBox(height: 24), _metricsCard(v)],
        const SizedBox(height: 24),
        const SectionHeader(title: 'Caption'),
        ChunkyTextField(
          key: const ValueKey('post-caption'),
          controller: _caption,
          hint: 'Tulis caption…',
          maxLines: 10,
          minLines: 4,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          inputFormatters: [LengthLimitingTextInputFormatter(captionMax)],
        ),
        _Counter(
          left: '${_caption.text.length}/$captionMax karakter',
          over: _caption.text.length > captionMax * 0.95,
        ),
        const SizedBox(height: 12),
        ChunkyTextField(
          key: const ValueKey('post-hashtags'),
          controller: _hashtags,
          label: 'Hashtag',
          hint: '#hemat #keuangan',
          maxLines: 4,
          minLines: 2,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.none,
          inputFormatters: [LengthLimitingTextInputFormatter(hashtagsMax)],
        ),
        _Counter(
          left:
              '${hashtagCount(_hashtags.text)} hashtag · ${_hashtags.text.length}/$hashtagsMax',
          over: _hashtags.text.length > hashtagsMax * 0.95,
        ),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Jadwal',
          trailing: _at == null || p.isPosted
              ? null
              : TextButton(
                  key: const ValueKey('post-unschedule'),
                  onPressed: () => setState(() => _at = null),
                  child: const Text('Hapus jadwal'),
                ),
        ),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: PickerField(
                key: const ValueKey('post-date'),
                label: 'Tanggal',
                value: _at == null ? null : contentDayLabel(_at!, now),
                placeholder: 'Belum dijadwal',
                leading: Icon(
                  Icons.event_rounded,
                  color: GhinaColors.blue.base,
                ),
                trailingIcon: Icons.calendar_month_rounded,
                onTap: _pickDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: PickerField(
                key: const ValueKey('post-time'),
                label: 'Jam',
                value: _at == null ? null : Fmt.time(_at!),
                placeholder: '--.--',
                trailingIcon: Icons.schedule_rounded,
                onTap: _pickTime,
              ),
            ),
          ],
        ),
        if (_at != null) ...[
          const SizedBox(height: 16),
          const FieldLabel('Ingatkan'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in contentRemindOptions)
                ChunkyChip(
                  key: ValueKey('remind-${m ?? 'none'}'),
                  label: remindLabel(m),
                  icon: m == null
                      ? Icons.notifications_off_rounded
                      : Icons.notifications_active_rounded,
                  selected: _remind == m,
                  color: GhinaColors.orange,
                  onTap: () => setState(() => _remind = m),
                ),
            ],
          ),
          if (_remind != null && account != null) ...[
            const SizedBox(height: 8),
            Text(
              'Notifikasi: [${account.code}-TAYANG] ${v.title}',
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ],
      ],
    );
  }

  Widget _metricsCard(ContentPostView v) {
    final g = context.ghina;
    final m = v.post.metrics;
    final rate = engagementRate(m);
    return ChunkyCard(
      key: const ValueKey('post-metrics'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Performa',
                  style: GhinaType.h2.copyWith(color: g.textPrimary),
                ),
              ),
              if (!m.isEmpty)
                ChunkyPill(
                  label:
                      'Eng. ${compactCount(m.engagement)}${rate == null ? '' : ' · ${percentLabel(rate)}'}',
                  color: GhinaColors.purple,
                  soft: true,
                  uppercase: false,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Isi manual dari insight aplikasinya. Boleh sebagian.',
            style: GhinaType.bodyS.copyWith(color: g.textSecondary),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (key, label, icon) in _metricKeys)
                    SizedBox(
                      width: w,
                      child: ChunkyTextField(
                        key: ValueKey('metric-$key'),
                        controller: _metric[key],
                        label: label,
                        hint: '0',
                        prefixIcon: icon,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          ChunkyButton(
            key: const ValueKey('metrics-save'),
            label: 'Simpan performa',
            icon: Icons.insights_rounded,
            color: GhinaColors.purple,
            size: ChunkyButtonSize.medium,
            onPressed: () => _saveMetrics(v),
          ),
        ],
      ),
    );
  }
}

int daysSince(DateTime at, DateTime now) => now.difference(at).inHours ~/ 24;

class _Counter extends StatelessWidget {
  const _Counter({required this.left, this.over = false});
  final String left;
  final bool over;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, right: 4),
    child: Text(
      left,
      textAlign: TextAlign.right,
      style: GhinaType.caption.copyWith(
        color: over ? GhinaColors.red.base : context.ghina.textMuted,
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.now});
  final ContentPostView view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final a = view.account;
    final p = view.post;
    final when = p.isPosted
        ? (p.postedAt == null
              ? 'Sudah tayang'
              : 'Tayang ${contentWhenLabel(p.postedAt!, now)}')
        : (p.scheduledAt == null
              ? 'Belum dijadwal'
              : 'Jadwal ${contentWhenLabel(p.scheduledAt!, now)}');
    return ChunkyCard(
      padding: const EdgeInsets.all(16),
      tinted: a == null ? null : readableSwatch(context, a.color),
      onTap: view.item == null
          ? null
          : () => context.push(contentItemRoute(view.item!.id)),
      child: Row(
        children: [
          if (a != null) AccountAvatar(account: a, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a == null
                      ? 'Akun terhapus'
                      : '${a.platformLabel} · ${a.atHandle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.bodyS
                      .w(800)
                      .copyWith(color: g.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  view.title.isEmpty ? 'Tanpa judul' : view.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PostStatusPill(status: p.status),
                    Text(
                      when,
                      key: const ValueKey('post-when'),
                      style: GhinaType.bodyS
                          .w(700)
                          .copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostedSheet extends StatefulWidget {
  const _PostedSheet({this.initialUrl});
  final String? initialUrl;

  @override
  State<_PostedSheet> createState() => _PostedSheetState();
}

class _PostedSheetState extends State<_PostedSheet> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim();
    if (t != null && t.isNotEmpty) setState(() => _url.text = t);
  }

  void _done() {
    final u = _url.text.trim();
    if (u.isNotEmpty && !isHttpUrl(u)) {
      setState(() => _error = 'Link harus diawali http:// atau https://');
      return;
    }
    Navigator.of(context).pop(u);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Mantap! Tempel link postingannya kalau mau (boleh dilewati).',
        style: GhinaType.body.copyWith(color: context.ghina.textSecondary),
      ),
      const SizedBox(height: 14),
      ChunkyTextField(
        key: const ValueKey('posted-url'),
        controller: _url,
        label: 'Link postingan',
        hint: 'https://…',
        keyboardType: TextInputType.url,
        textCapitalization: TextCapitalization.none,
        errorText: _error,
        suffix: IconButton(
          tooltip: 'Tempel',
          icon: const Icon(Icons.content_paste_rounded),
          onPressed: _paste,
        ),
      ),
      const SizedBox(height: 20),
      ChunkyButton(
        key: const ValueKey('posted-confirm'),
        label: 'Tandai tayang',
        icon: Icons.rocket_launch_rounded,
        color: GhinaColors.green,
        onPressed: _done,
      ),
    ],
  );
}
