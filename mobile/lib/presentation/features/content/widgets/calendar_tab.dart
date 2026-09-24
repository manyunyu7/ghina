import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/dates.dart';
import '../../../../core/formatters.dart';
import '../../../../di/di.dart';
import '../../../../domain/entities/entities.dart';
import '../../../../domain/usecases/usecases.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/widgets.dart';
import '../content_actions.dart';
import '../content_format.dart';
import 'content_visuals.dart';
import 'time_picker.dart';

enum _Mode { week, month }

/// Kalender: week strip or month grid of posts (colored by account), each
/// account's weekly target meter ("IG 1/3"), empty-slot hints, the selected
/// day's posts and rescheduling.
class ContentCalendarTab extends ConsumerStatefulWidget {
  const ContentCalendarTab({super.key});

  @override
  ConsumerState<ContentCalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends ConsumerState<ContentCalendarTab> {
  _Mode _mode = _Mode.week;
  late DateTime _day = startOfDay(ref.read(clockProvider).now());

  ({DateTime from, DateTime to}) get _range => _mode == _Mode.week
      ? weekRange(_day)
      : monthGridRange(YearMonth.of(_day));

  void _shift(int dir) => setState(() {
    _day = _mode == _Mode.week
        ? addDays(_day, 7 * dir)
        : DateTime(_day.year, _day.month + dir, 1);
  });

  @override
  Widget build(BuildContext context) {
    final now = ref.read(clockProvider).now();
    final today = startOfDay(now);
    final r = _range;
    final cal = ref.watch(watchContentCalendarProvider(r));
    final g = context.ghina;
    final label = _mode == _Mode.week
        ? weekRangeLabel(r.from, r.to)
        : Fmt.monthYear(_day);

    return RefreshIndicator(
      onRefresh: () => pullToSync(context, ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          GhinaSpace.page,
          4,
          GhinaSpace.page,
          120,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: ChunkySegmented<_Mode>(
                  height: 34,
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                  segments: const [
                    ChunkySegment(
                      value: _Mode.week,
                      label: 'Minggu',
                      color: GhinaColors.purple,
                    ),
                    ChunkySegment(
                      value: _Mode.month,
                      label: 'Bulan',
                      color: GhinaColors.purple,
                    ),
                  ],
                ),
              ),
              if (!isSameDay(_day, today)) ...[
                const SizedBox(width: 8),
                ChunkyButton(
                  key: const ValueKey('cal-today'),
                  label: 'Hari ini',
                  size: ChunkyButtonSize.small,
                  variant: ChunkyButtonVariant.outline,
                  expand: false,
                  onPressed: () => setState(() => _day = today),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ChunkyIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Sebelumnya',
                size: 40,
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Text(
                  label,
                  key: const ValueKey('cal-label'),
                  textAlign: TextAlign.center,
                  style: GhinaType.h3.copyWith(color: g.textPrimary),
                ),
              ),
              ChunkyIconButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Berikutnya',
                size: 40,
                onPressed: () => _shift(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...cal.when(
            skipLoadingOnReload: true,
            loading: () => [const Skeleton(height: 220, radius: GhinaRadii.xl)],
            error: (_, _) => [
              ErrorRetry(
                compact: true,
                onRetry: () => ref.invalidate(watchContentCalendarProvider(r)),
              ),
            ],
            data: (c) => _body(c, today),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(ContentCalendar c, DateTime today) {
    final ws = weekStartOf(_day);
    final week = c.weeks.where((w) => isSameDay(w.weekStart, ws)).firstOrNull;
    final dayPosts = c.on(dateKey(_day));
    final g = context.ghina;
    return [
      ChunkyCard(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        child: _mode == _Mode.week
            ? _WeekStrip(
                from: weekStartOf(_day),
                cal: c,
                selected: _day,
                today: today,
                onTap: (d) => setState(() => _day = d),
              )
            : _MonthGrid(
                month: YearMonth.of(_day),
                cal: c,
                selected: _day,
                today: today,
                onTap: (d) => setState(() => _day = d),
              ),
      ),
      if (week != null && week.accounts.isNotEmpty) ...[
        const SizedBox(height: 20),
        SectionHeader(
          title: isSameDay(ws, weekStartOf(today))
              ? 'Target minggu ini'
              : 'Target minggu ${ws.day}/${ws.month}',
        ),
        _TargetMeters(week: week),
        ..._emptyHint(week, ws, today),
      ],
      const SizedBox(height: 20),
      SectionHeader(
        title: Fmt.dateFull(_day),
        subtitle: dayPosts.isEmpty ? null : '${dayPosts.length} posting',
      ),
      if (dayPosts.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Belum ada posting di hari ini.',
            key: const ValueKey('cal-day-empty'),
            textAlign: TextAlign.center,
            style: GhinaType.body.copyWith(color: g.textSecondary),
          ),
        )
      else
        for (final p in dayPosts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PostRow(view: p, onTap: () => _postSheet(p)),
          ),
    ];
  }

  List<Widget> _emptyHint(CalendarWeek week, DateTime ws, DateTime today) {
    // Past weeks: no nudge.
    if (addDays(ws, 7).isBefore(today) || isSameDay(addDays(ws, 7), today)) {
      return const [];
    }
    final open = [
      for (final a in week.accounts)
        if (a.emptySlots > 0) a,
    ];
    if (open.isEmpty) return const [];
    final total = open.fold(0, (s, a) => s + a.emptySlots);
    final g = context.ghina;
    return [
      const SizedBox(height: 10),
      ChunkyCard(
        key: const ValueKey('cal-empty-hint'),
        tinted: GhinaColors.yellow,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              Icons.event_available_rounded,
              color: GhinaColors.yellow.edge,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Masih ada $total slot kosong: '
                '${open.map((a) => '${a.account.code} ${a.emptySlots}').join(', ')}. '
                'Jadwalkan konten yang sudah Siap, yuk!',
                style: GhinaType.bodyS.w(700).copyWith(color: g.textPrimary),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _postSheet(ContentPostView p) async {
    final action = await showChunkyBottomSheet<String>(
      context,
      title: p.title.isEmpty ? 'Posting' : p.title,
      showClose: true,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChunkyTile(
            key: const ValueKey('cal-open-post'),
            leading: const Icon(Icons.open_in_new_rounded),
            title: 'Buka posting',
            dense: true,
            onTap: () => Navigator.of(c).pop('open'),
          ),
          const SizedBox(height: 8),
          if (!p.post.isPosted)
            ChunkyTile(
              key: const ValueKey('cal-reschedule'),
              leading: const Icon(Icons.edit_calendar_rounded),
              title: 'Jadwal ulang',
              dense: true,
              onTap: () => Navigator.of(c).pop('reschedule'),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      context.push(contentPostRoute(p.id));
      return;
    }
    final at = await showRescheduleSheet(
      context,
      initial:
          p.post.scheduledAt ?? DateTime(_day.year, _day.month, _day.day, 19),
    );
    if (at == null || !mounted) return;
    final item = p.item;
    await postChangeFlow(
      context,
      ref,
      item: item,
      posts: [p.post],
      write: () => ref.read(scheduleContentPostProvider)(p.id, at),
      doneToast:
          'Dijadwalkan ${contentWhenLabel(at, ref.read(clockProvider).now())}',
    );
    if (mounted) setState(() => _day = startOfDay(at));
  }
}

/// Date + time sheet. Returns the new time, or null.
Future<DateTime?> showRescheduleSheet(
  BuildContext context, {
  required DateTime initial,
}) => showChunkyBottomSheet<DateTime>(
  context,
  title: 'Jadwal ulang',
  showClose: true,
  builder: (_) => _Reschedule(initial: initial),
);

class _Reschedule extends StatefulWidget {
  const _Reschedule({required this.initial});
  final DateTime initial;

  @override
  State<_Reschedule> createState() => _RescheduleState();
}

class _RescheduleState extends State<_Reschedule> {
  late DateTime _at = widget.initial;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DateField(
        label: 'Tanggal',
        value: _at,
        onChanged: (d) => setState(
          () => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute),
        ),
      ),
      const SizedBox(height: 12),
      PickerField(
        label: 'Jam',
        value: Fmt.time(_at),
        leading: const Icon(Icons.schedule_rounded),
        trailingIcon: Icons.access_time_rounded,
        onTap: () async {
          final hm = await showContentTimePicker(
            context,
            initial: formatHm(_at.hour, _at.minute),
          );
          if (hm == null) return;
          setState(
            () => _at = DateTime(
              _at.year,
              _at.month,
              _at.day,
              int.parse(hm.substring(0, 2)),
              int.parse(hm.substring(3, 5)),
            ),
          );
        },
      ),
      const SizedBox(height: 20),
      ChunkyButton(
        key: const ValueKey('reschedule-save'),
        label: 'Simpan jadwal',
        onPressed: () => Navigator.of(context).pop(_at),
      ),
    ],
  );
}

// ---------------------------------------------------------------- week strip

List<Color> _dayColors(BuildContext context, List<ContentPostView> posts) => [
  for (final p in posts) readableColor(context, p.color),
];

class _Dots extends StatelessWidget {
  const _Dots({required this.colors, this.size = 7});
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = colors.take(3).toList();
    return SizedBox(
      height: size + 2,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final c in shown)
            Container(
              width: size,
              height: size,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          if (colors.length > 3)
            Text(
              '+',
              style: GhinaType.caption
                  .w(900)
                  .copyWith(color: context.ghina.textSecondary, height: 0.9),
            ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.from,
    required this.cal,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime from;
  final ContentCalendar cal;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: _DayCell(
            day: addDays(from, i),
            posts: cal.on(dateKey(addDays(from, i))),
            selected: isSameDay(addDays(from, i), selected),
            today: isSameDay(addDays(from, i), today),
            showWeekday: true,
            onTap: () => onTap(addDays(from, i)),
          ),
        ),
    ],
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.posts,
    required this.selected,
    required this.today,
    required this.onTap,
    this.showWeekday = false,
    this.outside = false,
  });

  final DateTime day;
  final List<ContentPostView> posts;
  final bool selected;
  final bool today;
  final bool showWeekday;
  final bool outside;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final sw = GhinaColors.purple;
    final fg = selected ? sw.on : (outside ? g.textMuted : g.textPrimary);
    return Semantics(
      button: true,
      selected: selected,
      label: '${Fmt.dateFull(day)}, ${posts.length} posting',
      child: GestureDetector(
        key: ValueKey('cal-day-${dateKey(day)}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: AnimatedContainer(
            duration: GhinaMotion.fast,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: selected ? sw.base : Colors.transparent,
              borderRadius: GhinaRadii.rMd,
              border: Border.all(
                color: today && !selected ? sw.base : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showWeekday)
                  Text(
                    isoWeekdayShort[day.weekday - 1],
                    style: GhinaType.caption
                        .w(700)
                        .copyWith(color: selected ? sw.on : g.textSecondary),
                  ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    style: (showWeekday ? GhinaType.h3 : GhinaType.body.w(800))
                        .copyWith(color: fg),
                  ),
                ),
                const SizedBox(height: 3),
                _Dots(
                  colors: selected
                      ? [for (final _ in posts) sw.on]
                      : _dayColors(context, posts),
                  size: showWeekday ? 7 : 5,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.cal,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final YearMonth month;
  final ContentCalendar cal;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final r = monthGridRange(month);
    final days = daysBetween(r.to, r.from) + 1;
    return Column(
      children: [
        Row(
          children: [
            for (final w in isoWeekdayShort)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: GhinaType.caption
                      .w(800)
                      .copyWith(color: g.textSecondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < days ~/ 7; row++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final d = addDays(r.from, row * 7 + i);
                      return _DayCell(
                        day: d,
                        posts: cal.on(dateKey(d)),
                        selected: isSameDay(d, selected),
                        today: isSameDay(d, today),
                        outside: !month.contains(d),
                        onTap: () => onTap(d),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- targets

class _TargetMeters extends StatelessWidget {
  const _TargetMeters({required this.week});
  final CalendarWeek week;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    return ChunkyCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          for (final a in week.accounts) ...[
            if (a != week.accounts.first) const SizedBox(height: 12),
            Row(
              key: ValueKey('meter-${a.account.id}'),
              children: [
                AccountAvatar(account: a.account, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.account.atHandle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GhinaType.bodyS
                                  .w(700)
                                  .copyWith(color: g.textSecondary),
                            ),
                          ),
                          Text(
                            a.label.replaceFirst(':', ''),
                            key: ValueKey('meter-label-${a.account.id}'),
                            style: GhinaType.body
                                .w(900)
                                .copyWith(color: g.textPrimary),
                          ),
                          if (a.met) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: GhinaColors.green.base,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (a.target != null)
                        ChunkyProgressBar(
                          value: a.target! == 0
                              ? 0
                              : (a.count / a.target!).clamp(0.0, 1.0),
                          color: a.met
                              ? GhinaColors.green
                              : readableSwatch(context, a.account.color),
                          height: 10,
                        )
                      else
                        Text(
                          'Tanpa target',
                          style: GhinaType.caption.copyWith(color: g.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({required this.view, required this.onTap});
  final ContentPostView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.ghina;
    final at = view.post.calendarAt;
    return ChunkyCard(
      key: ValueKey('cal-post-${view.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              at == null ? '--' : Fmt.time(at),
              style: GhinaType.body.w(900).copyWith(color: g.textPrimary),
            ),
          ),
          if (view.account != null) ...[
            AccountAvatar(
              account: view.account!,
              size: 32,
              status: view.post.status,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.title.isEmpty ? 'Tanpa judul' : view.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.body.w(800).copyWith(color: g.textPrimary),
                ),
                Text(
                  view.account?.atHandle ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GhinaType.caption.copyWith(color: g.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PostStatusPill(status: view.post.status),
        ],
      ),
    );
  }
}
