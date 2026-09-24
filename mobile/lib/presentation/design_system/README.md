# Ghina design system

The Duolingo-flavored UI kit for Ghina: bright colors, chunky "3D" pressables, big
rounded Nunito type, and Ghina the money-tree mascot (a round leafy
crown with a face, bark trunk, twig arms and gold-coin fruits). **Build screens only
from these widgets.**

```dart
import 'package:ghina/presentation/design_system/design_system.dart';
```

The barrel exports everything. It's pure presentation: no data/di imports.

## Setup

```dart
MaterialApp.router(
  theme: GhinaTheme.light(),
  darkTheme: GhinaTheme.dark(),
  themeMode: ThemeMode.system,
);
```

Material components (AppBar, inputs, chips, dialogs, sheets, snackbars, switches,
progress, tabs, date picker…) are themed already. You can open
`gallery/ui_gallery_screen.dart` (`UiGalleryScreen`) to see every widget in light and dark.

## Tokens

| What | API |
|---|---|
| Brand swatches (`base` / `edge` / `light` / `on`) | `GhinaColors.green · blue · red · orange · yellow · purple · pink · lime · gray`, plus `bark` (mascot trunk brown) |
| Semantic | `GhinaColors.income` (green), `expense` (red), `transfer` (blue), `warning` (orange), `xp` (yellow), `streak`, `heart`, `gem`, `level` |
| Theme-aware neutrals | `context.ghina` → `background, surface, surfaceAlt, border, borderEdge, textPrimary, textSecondary, textMuted, isDark, tint(swatch)` |
| User colors (hex strings, the web palette) | `CategoryColors.palette`, `.parse('#f97316')`, `.toHex(c)`, `.swatch(hex)`, `.forKey(name)`; `ChunkySwatch.fromColor(c)` |
| Icons (lucide names ↔ Material) | `GhinaIcons.of('shopping-cart')` (also takes `HeartPulse`/snake_case), `.nameOf(icon)`, `.categoryNames`, `.walletType('ewallet')`, `.walletTypeLabels` |
| Spacing | `GhinaSpace.xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`, `GhinaSpace.page` (20), `gapLg`… |
| Radii | `GhinaRadii.rMd 12 · rLg 16 · rXl 20 · rXxl 28 · rPill` |
| Depth (bottom edge instead of shadow) | `GhinaDepth.sm 3 · md 4 · lg 6`, `border 2` |
| Motion | `GhinaMotion.press · fast · medium · slow · progress · countUp`, curves `standard · pop · bounce` |
| Money format | `GhinaMoney.format(25000)` → `Rp 25.000`; `compact: true` → `Rp 1,3 jt`; `showSign`; other currencies get 2 decimals |

### Typography (Nunito, variable font)

`GhinaType.moneyXL 44 · moneyL 30 · moneyM 17 · moneyS 13` (tabular figures),
`display 36 · h1 26 · h2 20 · h3 17 · bodyL 17 · body 15 · bodyS 13 · caption 12 · overline 13 caps · button 15 caps`.

⚠️ To change a weight, use `style.w(800)`, not `copyWith(fontWeight:)`. The font is
variable, and `.w()` also sets the `wght` axis.

## Widget catalog

### Actions
| Widget | Use |
|---|---|
| `ChunkyButton(label, onPressed, variant: primary/secondary/outline/danger/ghost, size: small/medium/large, icon, trailingIcon, loading, expand, color: swatch)` | All buttons. Large buttons expand to full width by default (put them in `Expanded` inside a `Row`). `onPressed: null` makes it disabled. Labels render in CAPS. Use one primary per screen. |
| `ChunkyIconButton(icon, onPressed, color?, size, tooltip)` | Close, back, +/- buttons. |
| `ChunkySurface(color, edgeColor, borderColor?, depth, onTap, child)` | Low-level press-down primitive for custom pressables. |

### Surfaces
| Widget | Use |
|---|---|
| `ChunkyCard(child, onTap?, color: swatch (solid) \| tinted: swatch (pale + border), padding)` | Every card. Neutral by default. |
| `ChunkyTile(title, subtitle, leading, trailing, onTap, showChevron, framed, dense, tinted, titleWidget)` | List rows (transactions, wallets, settings). `framed: false` gives flat rows inside one card. |
| `StatTile(icon, value, label, color)` | Small stat cards on home and profile. |
| `ChunkyPill(label, color, soft, icon)` | Tags like "BARU" or "LUNAS". |
| `SectionHeader(title, subtitle, actionLabel, onAction, trailing)` | Section titles, e.g. "Lihat semua". |
| `CategoryAvatar(iconName \| icon, colorHex \| color, size, soft)` | Category and wallet icons. |
| `MoneyText(amount \| text, currency, tone: auto/expense/income/transfer/neutral, style, countUp, compact, color)` | All money. Use `MoneyTone.expense` for expense amounts that are stored positive. |

### Input
| Widget | Use |
|---|---|
| `ChunkyTextField(label, hint, controller, errorText, prefixIcon, suffix, obscureText, keyboardType, validator, readOnly+onTap, …)` | Text inputs. It shakes when `errorText` changes and gets an eye toggle when obscured. It works in a `Form`. |
| `AmountController(currency, initial)` + `AmountDisplay(controller, color, label)` + `AmountKeypad(controller, onSubmit, submitLabel, quickAmounts)` | Fast amount entry. Read `controller.amount`. Submit is disabled at 0, and long-pressing ⌫ clears. |
| `ChunkySegmented<T>(segments: [ChunkySegment(value, label, icon, color)], value, onChanged)` | Pengeluaran / Pemasukan / Transfer. The thumb takes the segment's color. |
| `ChunkyChoiceChips<T>(options: [ChunkyChoice(...)], selected: Set, onChanged, multi, scrollable)` / `ChunkyChip` | Filters and choices. |
| `IconGridPicker(selected: 'utensils', onChanged, color, icons)` | Category icon picker. Works with name strings. |
| `ChunkyColorPicker(selected: '#f97316', onChanged)` | Category and wallet colors. Works with hex strings. |

### Progress and gamification
| Widget | Use |
|---|---|
| `ChunkyProgressBar(value, color, height, label)` / `ChunkyProgressBar.budget(used:)` | Lessons and budgets. The budget variant is green, then orange at 75%+, then red at 100%+. |
| `ProgressRing(value, size, stroke, color, child)` | Daily goal ring. |
| `StreakFlame(count, active, size, showCount)` | Streak. Gray when `active: false`. |
| `XpBadge(xp, plus, large)` · `LevelBadge(level, size, color)` · `HeartsRow(hearts, max)` · `GemCounter(gems)` · `StatPill(icon \| leading, value, color)` | Header counters and rewards. |
| `PathNode(state: locked/available/current/completed, icon, progress, onTap)` | Learning path nodes. The current node floats and shows "MULAI". |
| `QuizOptionTile(label, state: idle/selected/correct/wrong/disabled, index, onTap)` | Quiz answers. Wrong answers shake. |
| `AnswerFeedbackBar(correct, message, onContinue)` | "Mantap, benar!" / "Kurang tepat" banner at the bottom of the lesson screen. |

### Mascot
| Widget | Use |
|---|---|
| `MascotView(mood, size, animate, color)` | Ghina the money tree. Moods: `happy`, `excited` (branches up, sparkles, coins pop), `thinking` (twig on chin, thought dots), `sad` (drooping crown, tear, falling leaf, a coin on the ground), `sleeping` (Zzz), `waving`. The crown sways, leaves rustle and it blinks. `color` recolors the crown. The app icon and web logo are rendered from it (`test/tool/app_icon_render_test.dart`). |
| `MascotSpeech(message, title, mood, mascotSize, bubbleColor, action)` | Mascot plus speech bubble for tips and greetings. |

Pick the mood by situation:
- **waving**: greet or onboard.
- **happy**: default.
- **excited**: rewards.
- **thinking**: tips or loading.
- **sad**: over budget, errors, or a lost streak.
- **sleeping**: empty states.

### Feedback and overlays
| API | Use |
|---|---|
| `await showCelebration(context, title: 'Mantap!', subtitle, xp, streak, stats: [CelebrationStat(...)], buttonLabel)` | Full-screen "lesson complete" moment with confetti. Use it for big wins: daily goal met, streak milestone, lesson done, first transaction. |
| `showToastBadge(context, message, icon, color)` | Small toast that drops from the top. Use it for small wins (+XP) and confirmations like "Tersimpan offline". |
| `await showChunkyConfirm(context, title, message, confirmLabel, destructive)` → `bool` | Confirm dialogs. Destructive ones use a red button and the sad mascot. |
| `showChunkyDialog(context, builder)` + `ChunkyDialog(title, message, mood, content, actions)` | Custom dialogs. |
| `showChunkyBottomSheet<T>(context, title, builder, showClose)` / `ChunkyBottomSheet` | Pickers and the quick-add sheet. |
| `EmptyState(title, message, mood, actionLabel, onAction, compact)` | Empty lists. Always pair it with a CTA. |
| `Skeleton(width, height)` · `Skeleton.circle` · `SkeletonTile` · `SkeletonList(count)` | Loading states. Use these instead of spinners. |
| `SyncBadge(state: SyncIndicatorState.synced/syncing/offline/error, pendingCount, compact, onTap)` | Sync status in the AppBar. The sync layer maps its state to this enum. |
| `ChunkyNavBar(items: 4 × ChunkyNavItem, currentIndex, onTap, onCenterTap)` | Shell bottom bar with the big center "+" button. Use it as `Scaffold.bottomNavigationBar`. |

### Motion helpers
- `PopIn(child, delay, fromScale, slideY)`: entrance pop. Stagger list items with `delay: 60ms * i`.
- `Shake(trigger, child)`: shakes when `trigger` changes. Use it for errors.
- `Bounce(child)`: idle float.
- `Pulse(trigger, child)`: a "boing" when a counter changes.
- `ghinaPageRoute(builder)` / `ghinaSlideUpTransition` for GoRouter `CustomTransitionPage`. The theme already applies the transition on Android.

## Copy tone (Bahasa Indonesia)

- Keep it casual, warm, and encouraging. Say "kamu", never "Anda". Keep it short.
- Celebrate small wins: "Mantap!", "Keren!", "Hebat, streak kamu 5 hari! 🔥", "Target harian tercapai!"
- Be gentle when things go wrong, and never blame the user: "Yah, budget makan bulan ini kelewat dikit. Besok kita coba lagi ya 💪". For errors: "Ups, ada yang salah. Coba lagi, yuk."
- Empty states should invite action: "Belum ada transaksi. Catat yang pertama, yuk!"
- Offline: "Tersimpan di HP, nanti disinkron otomatis 👍"
- Button labels are short verbs: Simpan, Lanjut, Catat, Bayar, Hapus, Batal, Nanti saja, Lewati.
- Use emoji sparingly, one at most, at the end of a sentence.
- Money is `Rp 25.000` (dot thousands separator, no decimals). Use `GhinaMoney` or `MoneyText`.

## Layout guidance

- Page padding is 20 (`GhinaSpace.pagePadding`). Put 12–16 between cards and 24–28 between sections.
- The main CTA goes at the bottom of the screen as a full-width large `ChunkyButton`.
- Keep a clear hierarchy: one hero number (`moneyXL`) per screen, section titles in `h2`, rows in `h3`.
- Everything is rounded, and nothing uses blur shadows. Depth comes from the bottom edge.

## Testing notes

- Animated widgets repeat forever: `MascotView`, `StreakFlame`, `Skeleton`, `AmountDisplay`, the current `PathNode`, and `SyncBadge` while syncing. With these on screen, `pumpAndSettle()` never returns, so use `pump(Duration)` instead. `MascotView(animate: false)` and `StreakFlame(animate: false)` are static.
- Visual shots: `GHINA_SHOTS_DIR=/some/dir flutter test test/presentation/design_system/gallery_shots_test.dart` writes PNGs of every gallery section in light and dark. The test loads Nunito and the Material Icons font from the Flutter SDK (see `_helpers.dart`).
