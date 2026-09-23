# Ghina mobile — architecture

Flutter companion app for the Ghina web app (`../`). Offline-first, syncs with the
server per `../docs/mobile-sync.md`. Duolingo-style: bright, chunky, playful, rewarding.

## Stack

- State: `flutter_riverpod` 3 — plain providers, **no codegen** (no riverpod_generator).
- Local DB: `drift` + `drift_flutter` (codegen via `build_runner`, the only codegen we use).
- Network: `dio`. Token in `flutter_secure_storage`. Connectivity via `connectivity_plus`.
- Routing: `go_router`. Charts: `fl_chart`. Celebrations: `confetti`.
- Font: Nunito (variable, bundled at `assets/fonts/Nunito.ttf`).
- Run codegen: `dart run build_runner build --delete-conflicting-outputs`

## Language & tone

All UI copy is **Bahasa Indonesia**, casual and warm like Duolingo ("Mantap! 🔥 Streak
kamu 5 hari!"). Money is IDR by default, formatted `Rp 25.000` (use the user's currency).

## Clean Architecture (layer-first)

Dependency rule: **presentation → domain ← data**. `domain` is pure Dart: no Flutter,
no drift, no dio, no Riverpod, no shared_preferences imports. `presentation` never imports
`data` — it only knows domain entities and use cases. The only place that knows both is
the composition root `lib/di/`.

Layer-first (not feature-first) because entities are shared across features (a wallet is
used by transactions, budgets, subscriptions, forecast) and sync is cross-cutting.

```
lib/
  main.dart                    entry: ProviderScope + app
  app/                         app.dart (MaterialApp.router), router.dart (routes below)
  core/                        pure utilities usable by every layer: Failure types,
                               Result<T>, clock, id generation, money/date formatting
  domain/
    entities/                  immutable entities (Wallet, Transaction, Budget, …) + value
                               objects (Money, TxType, BillingCycle, …)
    repositories/              abstract repository interfaces
    usecases/                  one class per business operation, `call()` method
                               (CreateTransaction, TransferBetweenWallets,
                               PaySubscription, ComputeForecast, WatchDashboard, …)
    game/                      gamification engine: XP, streak, levels, hearts,
                               achievements, lesson engine, lesson content, GameStore
                               interface — all pure functions/classes
  data/
    datasources/local/         drift database, tables, DAOs
    datasources/remote/        dio client, auth API, sync API
    models/                    DTOs + mappers (DTO ⇄ drift row ⇄ domain entity)
    repositories/              implementations of domain/repositories
    sync/                      outbox + sync engine
    game/                      GameStore implementation (shared_preferences)
  di/                          composition root: Riverpod providers that bind
                               implementations to interfaces and build use cases
  presentation/
    design_system/             theme, tokens, typography, widgets, mascot, gallery
    state/                     app-wide Riverpod state/controllers (session, sync status,
                               game summary) built on use cases
    shared/                    cross-feature presentation code: rewards/ (XP toast +
                               celebrations, shown once), game_visuals.dart (mood/tier/icon
                               mapping), widgets/ (async states, month switcher, form
                               fields, date picker, pickers). See shared/README.md
    features/<feature>/        pages/, widgets/, controllers/ for one feature
test/                          mirrors lib/ (test/domain, test/data, test/presentation)
```

Errors: repositories/use cases throw or return typed `Failure`s from `core/`
(sealed class: network, unauthorized, validation, notFound, conflict, unknown). The
presentation layer maps failures to friendly Indonesian messages.

## Folder ownership during the build

| Owner | Folders |
|---|---|
| Data & sync agent | `core/`, `domain/entities`, `domain/repositories`, `domain/usecases`, `data/` (except `data/game`), `di/`, `presentation/state/` session + sync status |
| Design system agent | `presentation/design_system/` |
| Gamification agent | `domain/game/`, `data/game/`, `presentation/state/game/` |
| Screen agents (later) | `app/`, `presentation/features/**` |

## Screens & routes

Bottom navigation (StatefulShellRoute), 4 tabs + a big center "+" button that opens the
quick-add transaction sheet:

| Tab | Path | Screen |
|---|---|---|
| Beranda | `/home` | streak, daily goal ring, total balance, today's spending vs budget, hearts, mascot message, quick actions, recent transactions |
| Transaksi | `/transactions` | list grouped by date, filters, search |
| Belajar | `/learn` | Duolingo-style lesson path (financial literacy) |
| Profil | `/profile` | level, XP, streak calendar, achievements, links to everything else, settings |

Pushed routes (full screen, outside the shell):
`/login`, `/register`, `/onboarding`,
`/transactions/new`, `/transactions/:id`,
`/wallets`, `/wallets/new`, `/wallets/:id`,
`/categories`, `/categories/new`, `/categories/:id`,
`/budgets`, `/budgets/new`, `/budgets/:id`,
`/subscriptions`, `/subscriptions/new`, `/subscriptions/:id`,
`/forecast`, `/forecast/new`, `/forecast/:id`,
`/reports`,
`/prayers`, `/health`, `/health/new`, `/health/:id`, `/food`, `/food/new`, `/food/:id`,
`/achievements`, `/learn/lesson/:lessonId`, `/settings`, `/sync`.

## Feature parity with the web

Everything the web has: wallets (incl. transfers), transactions, categories (with default
set), monthly budgets, subscriptions (quick pay = create expense + advance next billing),
forecast (planned items + subscriptions + history projection — port
`../src/app/(dashboard)/forecast/logic.ts`), reports, prayers (5 daily, calendar),
health (weight / blood pressure), food log (photo, meal, calories), settings (currency,
sign out, reset local data).

## Gamification (local, derived from data — no server changes)

- XP from real activity: transaction logged, prayer, health entry, food log, lesson done,
  daily goal met, streak milestones.
- Streak: consecutive local days with at least one logged transaction (by `createdAt`).
  Streak freezes earned at milestones.
- Levels from total XP. Achievements/badges. Hearts = budget health for the month.
- Learning path: units of short Indonesian personal-finance lessons with quizzes.
- Progress that can't be derived from synced data (lesson progress, freezes, daily goal
  setting) is stored locally.

## Rules for contributors (humans and agents)

- Stay inside the folders you own; import others' public APIs, don't edit their files.
- Respect the dependency rule; `domain/` must compile without Flutter.
- `flutter analyze` must be clean for your files; add tests for logic.
- No network calls outside `data/datasources/remote/`. Screens use use cases (via `di/` providers) and `presentation/state/` only — never repositories or drift directly.
