import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/design_system/design_system.dart';
import '../presentation/features/auth/pages/login_page.dart';
import '../presentation/features/auth/pages/onboarding_page.dart';
import '../presentation/features/auth/pages/register_page.dart';
import '../presentation/features/budgets/pages/budget_form_page.dart';
import '../presentation/features/budgets/pages/budgets_page.dart';
import '../presentation/features/categories/pages/categories_page.dart';
import '../presentation/features/categories/pages/category_form_page.dart';
import '../presentation/features/food/pages/food_form_page.dart';
import '../presentation/features/food/pages/food_page.dart';
import '../presentation/features/forecast/pages/forecast_page.dart';
import '../presentation/features/forecast/pages/planned_form_page.dart';
import '../presentation/features/health/pages/health_form_page.dart';
import '../presentation/features/health/pages/health_page.dart';
import '../presentation/features/home/pages/home_page.dart';
import '../presentation/features/learn/pages/learn_page.dart';
import '../presentation/features/learn/pages/lesson_page.dart';
import '../presentation/features/prayers/pages/prayer_report_page.dart';
import '../presentation/features/prayers/pages/prayers_page.dart';
import '../presentation/features/profile/pages/achievements_page.dart';
import '../presentation/features/profile/pages/profile_page.dart';
import '../presentation/features/reports/pages/reports_page.dart';
import '../presentation/features/settings/pages/settings_page.dart';
import '../presentation/features/settings/pages/sync_page.dart';
import '../presentation/features/shell/app_shell.dart';
import '../presentation/features/subscriptions/pages/subscription_form_page.dart';
import '../presentation/features/subscriptions/pages/subscriptions_page.dart';
import '../presentation/features/transactions/pages/transaction_form_page.dart';
import '../presentation/features/transactions/pages/transactions_page.dart';
import '../presentation/features/wallets/pages/wallet_form_page.dart';
import '../presentation/features/wallets/pages/wallets_page.dart';
import '../presentation/state/game/game_providers.dart';
import '../presentation/state/session_controller.dart';

const _publicPaths = {'/login', '/register'};

/// Re-evaluates redirects whenever the session or onboarding state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(sessionControllerProvider, (_, _) => notifyListeners());
    ref.listen(onboardingDoneProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final session = ref.read(sessionControllerProvider);
      switch (session) {
        case SessionLoading():
          return loc == '/splash' ? null : '/splash';
        case SignedOut():
          return _publicPaths.contains(loc) ? null : '/login';
        case SignedIn():
          final onboarded = ref.read(onboardingDoneProvider).value;
          if (onboarded == null) return loc == '/splash' ? null : '/splash';
          if (!onboarded) return loc == '/onboarding' ? null : '/onboarding';
          if (loc == '/splash' ||
              loc == '/onboarding' ||
              _publicPaths.contains(loc)) {
            return '/home';
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/transactions',
                builder: (_, _) => const TransactionsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/learn', builder: (_, _) => const LearnPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
            ],
          ),
        ],
      ),
      ..._crud(
        '/transactions',
        const TransactionsPage(),
        (id) => TransactionFormPage(id: id),
        listInShell: true,
      ),
      ..._crud('/wallets', const WalletsPage(), (id) => WalletFormPage(id: id)),
      GoRoute(
        path: '/wallets/:id/history',
        builder: (_, s) => TransactionsPage(walletId: s.pathParameters['id']),
      ),
      ..._crud(
        '/categories',
        const CategoriesPage(),
        (id) => CategoryFormPage(id: id),
      ),
      ..._crud('/budgets', const BudgetsPage(), (id) => BudgetFormPage(id: id)),
      ..._crud(
        '/subscriptions',
        const SubscriptionsPage(),
        (id) => SubscriptionFormPage(id: id),
      ),
      ..._crud(
        '/forecast',
        const ForecastPage(),
        (id) => PlannedFormPage(id: id),
      ),
      ..._crud('/health', const HealthPage(), (id) => HealthFormPage(id: id)),
      ..._crud('/food', const FoodPage(), (id) => FoodFormPage(id: id)),
      GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
      GoRoute(path: '/prayers', builder: (_, _) => const PrayersPage()),
      GoRoute(
        path: '/prayers/report',
        builder: (_, _) => const PrayerReportPage(),
      ),
      GoRoute(
        path: '/achievements',
        builder: (_, _) => const AchievementsPage(),
      ),
      GoRoute(
        path: '/learn/lesson/:lessonId',
        builder: (_, s) => LessonPage(lessonId: s.pathParameters['lessonId']!),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/sync', builder: (_, _) => const SyncPage()),
    ],
  );
});

/// `<base>` list page, `<base>/new` and `<base>/:id` form pages.
List<GoRoute> _crud(
  String base,
  Widget list,
  Widget Function(String? id) form, {
  bool listInShell = false,
}) => [
  if (!listInShell) GoRoute(path: base, builder: (_, _) => list),
  GoRoute(path: '$base/new', builder: (_, _) => form(null)),
  GoRoute(path: '$base/:id', builder: (_, s) => form(s.pathParameters['id'])),
];

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: MascotView(mood: MascotMood.happy, size: 140)),
  );
}
