# presentation/shared

Presentation code used by more than one feature. Features import from here instead of
from each other (`features/a` never imports `features/b/widgets/...`). Built on
`design_system/`; may read `state/` and `di/` providers.

## `rewards/` — `import '.../shared/rewards/rewards.dart';`

The only place that shows reward moments and acknowledges them.

- `RewardTracker` — use around any write that can earn XP:
  ```dart
  final rewards = RewardTracker.start(ref);        // snapshot before the write
  final r = await ref.read(createFoodLogProvider)(input);
  if (r is Ok && mounted) {
    await rewards.finish(context,                  // wait → toast → celebrate
        xpToast: (xp) => 'Nyam! +$xp XP', doneToast: 'Tercatat 👍');
  }
  ```
  `finish` waits (≤1.5 s) until the game summary reflects the write (XP changed, or a
  new transaction/activity counted today even when XP is capped), toasts the XP gained
  (`xpToast`) or `doneToast`, optionally appends daily-goal progress (`goalHint`), then
  calls `presentPendingCelebrations`.
- `presentPendingCelebrations(context)` — shows daily goal → streak milestone → level
  up → new badges (sheet), then acknowledges exactly what was shown. Home calls it when
  it's the visible route.
- `presentNewAchievements(context, items)` — the same path for badges found unseen
  (achievements page).
- Once-only guarantee: `CelebrationGate` (`celebrationGateProvider`, one per
  `ProviderContainer`) remembers every moment claimed this session and runs one
  presentation at a time; concurrent callers wait, then skip what's already shown. A
  moment not shown (screen closed mid-way) is released and stays pending.

## `game_visuals.dart`

Engine → visuals mapping: `mascotMoodOf` (domain `MascotMood` → design-system
`MascotMood`; the two enums stay separate on purpose, this is the only conversion),
`tierSwatch` / `tierLabel`, `gameIcon`, `AchievementBadge`. When a file needs both
`MascotMood`s, import `domain/game/game.dart` with `hide MascotMood` (or `as game`).

## `widgets/` — `import '.../shared/widgets/widgets.dart';`

| File | What |
|---|---|
| `async_views.dart` | `ErrorRetry` (sad mascot + "Coba lagi"), `LoadingListView` (skeletons), `ScrollableFill` (pull-to-refresh on empty/error states) |
| `feedback.dart` | `showErrorToast`, `showFailureToast`, `showOkToast`, `pullToSync`, `popOr` |
| `month_switcher.dart` | `MonthSwitcher` (‹ month ›, tap for a month grid with "Bulan ini"), `showMonthPickerSheet`, `monthLabel` |
| `form_fields.dart` | `FieldLabel`, `PickerField`, `AmountField` + `AmountInputFormatter` (`25.000` as you type), `amountToInput`, `parseAmountInput` |
| `date_picker.dart` | `showGhinaDatePicker` (the app's only date picker: chunky Indonesian calendar sheet, Monday-first, "Hari ini", optional `firstDate`/`lastDate`), `DateField` |
| `entity_pickers.dart` | `showCategoryPickerSheet`, `showWalletPickerSheet` |
| `wallet_avatar.dart` | `WalletAvatar`, `walletIcon`, `walletIconOf` |
| `photo_viewer.dart` | Generic photos: `ViewerPhoto.file(path)` (local, not uploaded yet) / `ViewerPhoto.network(url)` (server path resolved with `AppConfig.resolveUrl`), `PhotoImage` (loading + broken placeholder), `showPhotoViewer(context, photos, initialIndex:, heroScope:)` → full-screen `PhotoViewer` (swipe, pinch/double-tap zoom, "2/4", close, "Belum diunggah" note for local files). Reusable by any feature (e.g. the food log photo). |
| `photo_strip.dart` | `PhotoStrip` (thumbnails → viewer with hero, remove "×", "+" tile, cloud badge on pending photos), `PhotoThumb`, `PhotoCountBadge` (list rows), `showPhotoAttachSheet` (Kamera / Galeri multi-select, count "2/5", max note), `pickPhotos` / `pickPhotosFrom` (chooser + friendly permission-denied toasts). Picking goes through `photoPickerProvider` (`PhotoPicker`, compressed `maxWidth: 1600, imageQuality: 80`); override it in tests. |

Feature-only widgets stay in their feature (e.g. `subscriptions/widgets/due_chip.dart`).
