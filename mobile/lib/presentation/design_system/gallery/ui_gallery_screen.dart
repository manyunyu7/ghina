import 'package:flutter/material.dart';

import '../design_system.dart';

/// Review screen showing every design-system widget. Toggle light/dark
/// with the top-right button. Not part of the product navigation.
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UiGalleryScreen()));
/// ```
class UiGalleryScreen extends StatefulWidget {
  const UiGalleryScreen({super.key, this.initialDark = false});

  final bool initialDark;

  @override
  State<UiGalleryScreen> createState() => _UiGalleryScreenState();
}

class _UiGalleryScreenState extends State<UiGalleryScreen> {
  late bool _dark = widget.initialDark;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _dark ? GhinaTheme.dark() : GhinaTheme.light(),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Ghina UI'),
              actions: [
                IconButton(
                  tooltip: 'Ganti tema',
                  onPressed: () => setState(() => _dark = !_dark),
                  icon: Icon(
                    _dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  ),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                for (final s in UiGallery.sections) ...[
                  SectionHeader(title: s.title),
                  s.builder(context),
                  const SizedBox(height: 28),
                ],
              ],
            ),
            bottomNavigationBar: ChunkyNavBar(
              currentIndex: _tab,
              onTap: (i) => setState(() => _tab = i),
              onCenterTap: () => showCelebration(
                context,
                xp: 15,
                streak: 6,
                subtitle: 'Kamu mencatat 3 transaksi hari ini.',
              ),
              items: UiGallery.navItems,
            ),
          );
        },
      ),
    );
  }
}

/// A named gallery section.
class GallerySection {
  const GallerySection(this.title, this.builder);

  final String title;
  final WidgetBuilder builder;
}

/// Gallery content, split into sections (also used by screenshot tests).
abstract final class UiGallery {
  static const navItems = [
    ChunkyNavItem(icon: Icons.home_rounded, label: 'Beranda'),
    ChunkyNavItem(icon: Icons.receipt_long_rounded, label: 'Transaksi'),
    ChunkyNavItem(icon: Icons.school_rounded, label: 'Belajar'),
    ChunkyNavItem(icon: Icons.person_rounded, label: 'Profil'),
  ];

  static final sections = <GallerySection>[
    GallerySection('Warna', (_) => const _Palette()),
    GallerySection('Tipografi', (_) => const _Typography()),
    GallerySection('Tombol', (_) => const _Buttons()),
    GallerySection('Kartu & tile', (_) => const _Cards()),
    GallerySection('Input', (_) => const _Inputs()),
    GallerySection('Keypad nominal', (_) => const _Keypad()),
    GallerySection('Pilih ikon & warna', (_) => const _Pickers()),
    GallerySection('Progres & gamifikasi', (_) => const _Game()),
    GallerySection('Maskot Ghina', (_) => const _Mascots()),
    GallerySection('Belajar', (_) => const _Learning()),
    GallerySection('Status & feedback', (_) => const _Feedback()),
  ];
}

// ---------------------------------------------------------------------------

class _Palette extends StatelessWidget {
  const _Palette();

  @override
  Widget build(BuildContext context) {
    const named = {
      'green': GhinaColors.green,
      'blue': GhinaColors.blue,
      'red': GhinaColors.red,
      'orange': GhinaColors.orange,
      'yellow': GhinaColors.yellow,
      'purple': GhinaColors.purple,
      'pink': GhinaColors.pink,
      'lime': GhinaColors.lime,
    };
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final e in named.entries)
          SizedBox(
            width: 76,
            child: Column(
              children: [
                ChunkySurface(
                  color: e.value.base,
                  edgeColor: e.value.edge,
                  onTap: () {},
                  child: const SizedBox(width: 76, height: 48),
                ),
                const SizedBox(height: 4),
                Text(
                  e.key,
                  style: GhinaType.caption.copyWith(
                    color: context.ghina.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Typography extends StatelessWidget {
  const _Typography();

  @override
  Widget build(BuildContext context) {
    final c = context.ghina.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mantap!',
          style: GhinaType.display.copyWith(color: GhinaColors.yellow.base),
        ),
        Text('Rp 12.450.000', style: GhinaType.moneyXL.copyWith(color: c)),
        Text('Judul layar', style: GhinaType.h1.copyWith(color: c)),
        Text('Judul kartu', style: GhinaType.h2.copyWith(color: c)),
        Text('Judul tile', style: GhinaType.h3.copyWith(color: c)),
        Text(
          'Teks isi yang ramah dan jelas dibaca.',
          style: GhinaType.body.copyWith(color: c),
        ),
        Text(
          'Keterangan kecil · 12:30',
          style: GhinaType.caption.copyWith(color: context.ghina.textSecondary),
        ),
        Text(
          'TOTAL XP',
          style: GhinaType.overline.copyWith(
            color: context.ghina.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Buttons extends StatefulWidget {
  const _Buttons();

  @override
  State<_Buttons> createState() => _ButtonsState();
}

class _ButtonsState extends State<_Buttons> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ChunkyButton(label: 'Lanjut', onPressed: () {}),
        const SizedBox(height: 12),
        ChunkyButton(
          label: 'Simpan',
          icon: Icons.check_rounded,
          variant: ChunkyButtonVariant.secondary,
          loading: _loading,
          onPressed: () {
            setState(() => _loading = true);
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _loading = false);
            });
          },
        ),
        const SizedBox(height: 12),
        ChunkyButton(
          label: 'Nanti saja',
          variant: ChunkyButtonVariant.outline,
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        ChunkyButton(
          label: 'Hapus',
          icon: Icons.delete_rounded,
          variant: ChunkyButtonVariant.danger,
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        const ChunkyButton(label: 'Belum bisa', onPressed: null),
        const SizedBox(height: 4),
        ChunkyButton(
          label: 'Lewati',
          variant: ChunkyButtonVariant.ghost,
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChunkyButton(
              label: 'Bayar',
              size: ChunkyButtonSize.small,
              onPressed: () {},
            ),
            ChunkyButton(
              label: 'Klaim',
              size: ChunkyButtonSize.medium,
              color: GhinaColors.yellow,
              icon: Icons.bolt_rounded,
              onPressed: () {},
            ),
            ChunkyIconButton(icon: Icons.close_rounded, onPressed: () {}),
            ChunkyIconButton(
              icon: Icons.add_rounded,
              color: GhinaColors.green,
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkyCard(
          color: GhinaColors.green,
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL SALDO',
                style: GhinaType.overline.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              MoneyText(
                amount: 12450000,
                tone: MoneyTone.neutral,
                color: Colors.white,
                style: GhinaType.moneyL,
                countUp: true,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.trending_up_rounded, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    '+Rp 350.000 minggu ini',
                    style: GhinaType.body.w(800).copyWith(color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ChunkyTile(
          leading: const CategoryAvatar(
            iconName: 'utensils',
            colorHex: '#f97316',
          ),
          title: 'Makan siang',
          subtitle: 'Dompet · 12:30',
          trailing: const MoneyText(amount: 25000, tone: MoneyTone.expense),
          onTap: () {},
        ),
        const SizedBox(height: 10),
        ChunkyTile(
          leading: const CategoryAvatar(
            iconName: 'briefcase',
            colorHex: '#16a34a',
          ),
          title: 'Gaji September',
          subtitle: 'BCA · 08:00',
          trailing: const MoneyText(amount: 8500000, tone: MoneyTone.income),
          onTap: () {},
        ),
        const SizedBox(height: 10),
        ChunkyTile(
          leading: const CategoryAvatar(
            iconName: 'arrow-left-right',
            colorHex: '#0ea5e9',
            soft: true,
          ),
          titleWidget: Row(
            children: [
              Text(
                'Transfer',
                style: GhinaType.h3.copyWith(color: g.textPrimary),
              ),
              const SizedBox(width: 8),
              const ChunkyPill(label: 'Baru', color: GhinaColors.purple),
            ],
          ),
          title: 'Transfer',
          subtitle: 'BCA ke GoPay',
          trailing: const MoneyText(amount: 200000, tone: MoneyTone.transfer),
          showChevron: true,
          onTap: () {},
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.local_fire_department_rounded,
                color: GhinaColors.orange,
                value: '12',
                label: 'Hari streak',
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: Icons.bolt_rounded,
                color: GhinaColors.yellow,
                value: '1.240',
                label: 'Total XP',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ChunkyCard(
          tinted: GhinaColors.blue,
          child: Text(
            'Kartu tinted untuk sorotan / terpilih.',
            style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _Inputs extends StatefulWidget {
  const _Inputs();

  @override
  State<_Inputs> createState() => _InputsState();
}

class _InputsState extends State<_Inputs> {
  String _filter = 'all';
  String _kind = 'expense';
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChunkySegmented<String>(
          segments: const [
            ChunkySegment(
              value: 'expense',
              label: 'Pengeluaran',
              color: GhinaColors.red,
            ),
            ChunkySegment(
              value: 'income',
              label: 'Pemasukan',
              color: GhinaColors.green,
            ),
            ChunkySegment(
              value: 'transfer',
              label: 'Transfer',
              color: GhinaColors.blue,
            ),
          ],
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 16),
        ChunkyChoiceChips<String>(
          options: const [
            ChunkyChoice(value: 'all', label: 'Semua'),
            ChunkyChoice(
              value: 'out',
              label: 'Keluar',
              icon: Icons.south_west_rounded,
              color: GhinaColors.red,
            ),
            ChunkyChoice(
              value: 'in',
              label: 'Masuk',
              icon: Icons.north_east_rounded,
              color: GhinaColors.green,
            ),
            ChunkyChoice(
              value: 'month',
              label: 'Bulan ini',
              icon: Icons.calendar_month_rounded,
            ),
          ],
          selected: {_filter},
          onChanged: (s) => setState(() => _filter = s.first),
        ),
        const SizedBox(height: 16),
        const ChunkyTextField(
          label: 'Catatan',
          hint: 'Contoh: makan siang bareng tim',
          prefixIcon: Icons.edit_note_rounded,
        ),
        const SizedBox(height: 14),
        ChunkyTextField(
          label: 'Email',
          hint: 'nama@email.com',
          errorText: _error,
          onChanged: (v) => setState(
            () => _error = v.contains('@') || v.isEmpty
                ? null
                : 'Email belum valid',
          ),
        ),
        const SizedBox(height: 14),
        const ChunkyTextField(
          label: 'Kata sandi',
          obscureText: true,
          hint: '••••••••',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Pengingat harian',
              style: GhinaType.body
                  .w(800)
                  .copyWith(color: context.ghina.textPrimary),
            ),
            const Spacer(),
            Switch(value: true, onChanged: (_) {}),
          ],
        ),
      ],
    );
  }
}

class _Keypad extends StatefulWidget {
  const _Keypad();

  @override
  State<_Keypad> createState() => _KeypadState();
}

class _KeypadState extends State<_Keypad> {
  final _amount = AmountController(initial: 25000);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AmountDisplay(
          controller: _amount,
          color: GhinaColors.red,
          label: 'Pengeluaran',
        ),
        const SizedBox(height: 16),
        AmountKeypad(
          controller: _amount,
          quickAmounts: const [10000, 20000, 50000, 100000],
          submitLabel: 'Simpan',
          onSubmit: () => showToastBadge(
            context,
            message: '+10 XP',
            icon: Icons.bolt_rounded,
          ),
        ),
      ],
    );
  }
}

class _Pickers extends StatefulWidget {
  const _Pickers();

  @override
  State<_Pickers> createState() => _PickersState();
}

class _PickersState extends State<_Pickers> {
  String _icon = 'utensils';
  String _color = '#f97316';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: CategoryAvatar(iconName: _icon, colorHex: _color, size: 64),
        ),
        const SizedBox(height: 16),
        ChunkyColorPicker(
          selected: _color,
          onChanged: (c) => setState(() => _color = c),
        ),
        const SizedBox(height: 16),
        IconGridPicker(
          selected: _icon,
          color: CategoryColors.parse(_color),
          onChanged: (n) => setState(() => _icon = n),
        ),
      ],
    );
  }
}

class _Game extends StatelessWidget {
  const _Game();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const StreakFlame(count: 12),
            const GemCounter(gems: 120),
            StatPill(
              icon: Icons.bolt_rounded,
              value: '1.240',
              color: GhinaColors.yellow,
            ),
            const HeartsRow(hearts: 3, size: 22),
          ],
        ),
        const SizedBox(height: 18),
        const ChunkyProgressBar(value: 0.62),
        const SizedBox(height: 12),
        ChunkyProgressBar.budget(
          used: 0.86,
          height: 22,
          label: 'Rp 860rb / Rp 1jt',
        ),
        const SizedBox(height: 12),
        ChunkyProgressBar.budget(used: 1.1, height: 12),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ProgressRing(
              value: 0.6,
              size: 120,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '30',
                    style: GhinaType.h1.w(900).copyWith(color: g.textPrimary),
                  ),
                  Text(
                    '/ 50 XP',
                    style: GhinaType.caption.copyWith(color: g.textSecondary),
                  ),
                ],
              ),
            ),
            const Column(
              children: [
                StreakFlame(count: 30, size: 72, showCount: false),
                SizedBox(height: 8),
                StreakFlame(count: 0, active: false, size: 24),
              ],
            ),
            const Column(
              children: [
                LevelBadge(level: 7, size: 56),
                SizedBox(height: 10),
                XpBadge(xp: 15),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _Mascots extends StatelessWidget {
  const _Mascots();

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 12,
          children: [
            for (final m in MascotMood.values)
              SizedBox(
                width: 110,
                child: Column(
                  children: [
                    MascotView(mood: m, size: 100),
                    Text(
                      m.name,
                      style: GhinaType.caption.copyWith(color: g.textSecondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Small sizes + crown recolors (seasons!).
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const MascotView(size: 48, animate: false),
            const MascotView(size: 72, animate: false),
            const MascotView(size: 72, color: GhinaColors.orange),
            const MascotView(size: 72, color: GhinaColors.pink),
            Text(
              '48 · 72 · warna',
              style: GhinaType.caption.copyWith(color: g.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const MascotSpeech(
          mood: MascotMood.waving,
          message: 'Halo! Yuk catat pengeluaran pertamamu hari ini 💪',
        ),
        const SizedBox(height: 12),
        const MascotSpeech(
          mood: MascotMood.thinking,
          title: 'Tips hemat',
          message: 'Sisihkan 10% gaji di awal bulan, bukan di akhir.',
          bubbleColor: GhinaColors.blue,
          mascotSize: 80,
        ),
      ],
    );
  }
}

class _Learning extends StatefulWidget {
  const _Learning();

  @override
  State<_Learning> createState() => _LearningState();
}

class _LearningState extends State<_Learning> {
  int? _sel;
  bool _checked = false;

  QuizOptionState _state(int i) {
    if (!_checked) {
      return _sel == i ? QuizOptionState.selected : QuizOptionState.idle;
    }
    if (i == 2) return QuizOptionState.correct;
    if (i == _sel) return QuizOptionState.wrong;
    return QuizOptionState.disabled;
  }

  @override
  Widget build(BuildContext context) {
    const opts = ['Beli gadget baru', 'Dana darurat', 'Liburan'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            PathNode(state: PathNodeState.completed, icon: Icons.star_rounded),
            PathNode(
              state: PathNodeState.current,
              icon: Icons.savings_rounded,
              progress: 0.4,
            ),
            PathNode(state: PathNodeState.locked, icon: Icons.star_rounded),
          ],
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < opts.length; i++) ...[
          QuizOptionTile(
            label: opts[i],
            index: i + 1,
            state: _state(i + 1),
            onTap: _checked ? null : () => setState(() => _sel = i + 1),
          ),
          const SizedBox(height: 10),
        ],
        if (!_checked)
          ChunkyButton(
            label: 'Periksa',
            onPressed: _sel == null
                ? null
                : () => setState(() => _checked = true),
          )
        else
          ClipRRect(
            borderRadius: GhinaRadii.rLg,
            child: AnswerFeedbackBar(
              correct: _sel == 2,
              message: _sel == 2 ? null : 'Jawaban yang benar: Dana darurat',
              onContinue: () => setState(() {
                _checked = false;
                _sel = null;
              }),
            ),
          ),
      ],
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SyncBadge(state: SyncIndicatorState.synced),
            SyncBadge(state: SyncIndicatorState.syncing, pendingCount: 2),
            SyncBadge(state: SyncIndicatorState.offline, pendingCount: 3),
            SyncBadge(state: SyncIndicatorState.error),
            SyncBadge(state: SyncIndicatorState.synced, compact: true),
          ],
        ),
        const SizedBox(height: 16),
        const SkeletonList(count: 2),
        const SizedBox(height: 16),
        const ChunkyCard(
          child: EmptyState(
            compact: true,
            title: 'Belum ada transaksi',
            message: 'Catat pengeluaran pertamamu, biar Ghina bangun!',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChunkyButton(
              label: 'Rayakan',
              size: ChunkyButtonSize.medium,
              color: GhinaColors.yellow,
              onPressed: () => showCelebration(
                context,
                xp: 15,
                streak: 6,
                subtitle: 'Kamu mencatat 3 transaksi hari ini.',
              ),
            ),
            ChunkyButton(
              label: 'Toast',
              size: ChunkyButtonSize.medium,
              variant: ChunkyButtonVariant.secondary,
              onPressed: () => showToastBadge(
                context,
                message: 'Pencapaian baru: Hemat Pangkal Kaya!',
                icon: Icons.emoji_events_rounded,
              ),
            ),
            ChunkyButton(
              label: 'Dialog',
              size: ChunkyButtonSize.medium,
              variant: ChunkyButtonVariant.danger,
              onPressed: () => showChunkyConfirm(
                context,
                title: 'Hapus transaksi?',
                message: 'Transaksi ini akan dihapus permanen.',
                confirmLabel: 'Hapus',
                destructive: true,
              ),
            ),
            ChunkyButton(
              label: 'Sheet',
              size: ChunkyButtonSize.medium,
              variant: ChunkyButtonVariant.outline,
              onPressed: () => showChunkyBottomSheet<void>(
                context,
                title: 'Pilih dompet',
                showClose: true,
                builder: (c) => Column(
                  children: [
                    for (final w in const [
                      ('Tunai', 'cash'),
                      ('BCA', 'bank'),
                      ('GoPay', 'ewallet'),
                    ]) ...[
                      ChunkyTile(
                        leading: CategoryAvatar(
                          icon: GhinaIcons.walletType(w.$2),
                          color: CategoryColors.forKey(w.$1),
                        ),
                        title: w.$1,
                        onTap: () => Navigator.pop(c),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
