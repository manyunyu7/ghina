/// Shared setup for the Catatan screen tests: real use cases over in-memory
/// repositories, fixed clock, the game engine (XP toasts), and scriptable
/// platform fakes (recorder, mic permission, transcriber, share intake).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/clock.dart';
import 'package:ghina/data/platform/fakes.dart';
import 'package:ghina/di/core_providers.dart';
import 'package:ghina/di/game_overrides.dart';
import 'package:ghina/domain/entities/entities.dart';
import 'package:ghina/domain/game/game.dart' hide MascotMood;
import 'package:ghina/domain/repositories/repositories.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/features/notes/pages/note_editor_page.dart';
import 'package:ghina/presentation/features/notes/pages/note_labels_page.dart';
import 'package:ghina/presentation/features/notes/pages/notes_page.dart';
import 'package:ghina/presentation/features/shell/share_intake_listener.dart';
import 'package:ghina/presentation/shared/widgets/widgets.dart';
import 'package:ghina/presentation/state/game/game_providers.dart';
import 'package:ghina/presentation/state/platform/platform_state.dart';
import 'package:ghina/presentation/state/session_controller.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/fakes.dart';
import '../profile/_harness.dart'
    show FakeFoodRepository, FakeHealthRepository, FakePrayerRepository;
import '../shell/test_utils.dart' show FakeSession;

/// Wednesday 23 September 2026, 10:00.
final notesNow = DateTime(2026, 9, 23, 10);

const notesUser = AppUser(
  id: 'u1',
  name: 'Ghina Putri',
  email: 'ghina@contoh.id',
  currency: 'IDR',
  syncEpoch: 'e1',
);

class FakeSeedState implements DefaultsSeedState {
  bool notesSeeded = false;
  @override
  Future<bool> notesServerSeeded() async => notesSeeded;
  @override
  Future<bool> contentServerSeeded() async => true;
}

class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker([this.paths = const ['/tmp/p1.jpg']]);
  List<String> paths;
  @override
  Future<List<String>> pick(PhotoSource source, {required int limit}) async =>
      paths.take(limit).toList();
}

class _SyncService implements SyncService {
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> syncNow() async {}
  @override
  Stream<SyncStatus> watchStatus() => Stream.value(SyncStatus.initial);
  @override
  Future<void> resetLocalData() async {}
}

Note note(
  String id, {
  String? title,
  String body = '',
  List<ChecklistItem> checklist = const [],
  List<String> labels = const [],
  String? color,
  bool pinned = false,
  bool archived = false,
  List<TransactionPhoto> photos = const [],
  List<NoteAudio> audio = const [],
  List<NoteLink> links = const [],
  int ageMinutes = 0,
}) => Note(
  id: id,
  title: title,
  body: body,
  checklist: checklist,
  labelIds: labels,
  color: color,
  pinned: pinned,
  archived: archived,
  photos: photos,
  audio: audio,
  links: links,
  createdAt: notesNow.subtract(Duration(minutes: ageMinutes + 5)),
  updatedAt: notesNow.subtract(Duration(minutes: ageMinutes)),
);

NoteLabel label(
  String id,
  String name, {
  String color = '#1cb0f6',
  bool tab = false,
  int order = 0,
}) => NoteLabel(
  id: id,
  name: name,
  color: color,
  pinnedTab: tab,
  sortOrder: order,
  createdAt: notesNow,
  updatedAt: notesNow,
);

Wallet wallet(String id, String name) => Wallet(
  id: id,
  name: name,
  type: WalletType.cash,
  balance: 500000,
  syncedBalance: 500000,
  currency: 'IDR',
  color: '#22c55e',
  icon: 'cash',
  archived: false,
  createdAt: notesNow,
  updatedAt: notesNow,
);

TaskArea area(String id, String name, String code, {int order = 0}) => TaskArea(
  id: id,
  name: name,
  code: code,
  sortOrder: order,
  createdAt: notesNow,
  updatedAt: notesNow,
);

class NotesHarness {
  NotesHarness({this.maxVoice});

  final Duration? maxVoice;
  final clock = FixedClock(notesNow);
  final gameStore = InMemoryGameStore({
    GameLocalState.storageKey: const GameLocalState(
      onboardingDone: true,
    ).encode(),
  });
  final notes = FakeNoteRepository();
  final labels = FakeNoteLabelRepository();
  final tasks = FakeTaskRepository();
  final areas = FakeTaskAreaRepository();
  final wallets = FakeWalletRepository();
  final categories = FakeCategoryRepository();
  final transactions = FakeTransactionRepository();
  final budgets = FakeBudgetRepository();
  final contentItems = FakeContentItemRepository();
  final contentPosts = FakeContentPostRepository();
  final accounts = FakeSocialAccountRepository();
  final pillars = FakeContentPillarRepository();
  final prayers = FakePrayerRepository();
  final health = FakeHealthRepository();
  final food = FakeFoodRepository();
  final seed = FakeSeedState();
  final recorder = FakeVoiceRecorder();
  final mic = FakeMicrophonePermission();
  final transcriber = FakeSpeechTranscriber();
  final share = FakeShareIntake();
  final picker = FakePhotoPicker();
  late final session = FakeSession(const SignedIn(notesUser));

  Note? noteById(String id) => notes.s.items[id];
  List<Note> get allNotes => notes.s.items.values.toList();

  List<Override> get overrides => [
    ...buildGameOverrides(store: gameStore),
    gameTickProvider.overrideWith((ref) => const Stream.empty()),
    clockProvider.overrideWithValue(clock),
    tickSourceProvider.overrideWithValue(() => Stream.value(notesNow)),
    noteRepositoryProvider.overrideWithValue(notes),
    noteLabelRepositoryProvider.overrideWithValue(labels),
    taskRepositoryProvider.overrideWithValue(tasks),
    taskAreaRepositoryProvider.overrideWithValue(areas),
    walletRepositoryProvider.overrideWithValue(wallets),
    categoryRepositoryProvider.overrideWithValue(categories),
    transactionRepositoryProvider.overrideWithValue(transactions),
    budgetRepositoryProvider.overrideWithValue(budgets),
    contentItemRepositoryProvider.overrideWithValue(contentItems),
    contentPostRepositoryProvider.overrideWithValue(contentPosts),
    socialAccountRepositoryProvider.overrideWithValue(accounts),
    contentPillarRepositoryProvider.overrideWithValue(pillars),
    prayerRepositoryProvider.overrideWithValue(prayers),
    healthRepositoryProvider.overrideWithValue(health),
    foodRepositoryProvider.overrideWithValue(food),
    defaultsSeedStateProvider.overrideWithValue(seed),
    unitOfWorkProvider.overrideWithValue(FakeUnitOfWork()),
    syncServiceProvider.overrideWithValue(_SyncService()),
    sessionControllerProvider.overrideWith(() => session),
    voiceRecorderProvider.overrideWithValue(recorder),
    microphonePermissionProvider.overrideWithValue(mic),
    speechTranscriberProvider.overrideWithValue(transcriber),
    audioPlaybackProvider.overrideWithValue(const NoopAudioPlayback()),
    shareIntakeProvider.overrideWithValue(share),
    photoPickerProvider.overrideWithValue(picker),
    if (maxVoice != null) maxVoiceDurationProvider.overrideWithValue(maxVoice!),
  ];
}

/// The app's notes routes (same shapes as `lib/app/router.dart`); other
/// routes render `route:<uri>`.
final notesRoutes = <RouteBase>[
  GoRoute(path: '/notes', builder: (_, _) => const NotesPage()),
  GoRoute(path: '/notes/labels', builder: (_, _) => const NoteLabelsPage()),
  GoRoute(path: '/notes/new', builder: (_, _) => const NoteEditorPage()),
  GoRoute(
    path: '/notes/:id',
    builder: (_, s) => NoteEditorPage(id: s.pathParameters['id']),
  ),
];

/// Pumps [location] pushed over a `HOME` stub (wrapped in the share listener
/// when [withShareListener], like the app shell).
Future<GoRouter> pumpNotes(
  WidgetTester tester,
  NotesHarness h, {
  String location = '/notes',
  Object? extra,
  bool dark = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  Key? boundaryKey,
  bool withShareListener = false,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) {
          const home = Scaffold(body: Center(child: Text('HOME')));
          return withShareListener
              ? const ShareIntakeListener(child: home)
              : home;
        },
      ),
      ...notesRoutes,
    ],
    errorBuilder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: ProviderScope(
        overrides: h.overrides,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: GhinaTheme.light(),
          darkTheme: GhinaTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  if (location != '/') unawaited(router.push(location, extra: extra));
  await settle(tester);
  return router;
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits for the editor's autosave debounce and the save itself.
Future<void> autosave(WidgetTester tester) async {
  await tester.pump(NoteEditorPage.autosaveDelay);
  await settle(tester, 4);
}
