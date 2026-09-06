import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/categories/presentation/category_management_page.dart';
import '../features/groups/group_providers.dart';
import '../features/groups/presentation/group_details_page.dart';
import '../features/groups/presentation/group_setup_page.dart';
import '../features/monitoring/monitoring_providers.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shopping/presentation/purchase_history_page.dart';
import '../features/shopping/presentation/shopping_page.dart';
import '../shared/main_scaffold.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final analyticsObserver = ref
      .watch(analyticsServiceProvider)
      .navigatorObserver;
  final router = GoRouter(
    initialLocation: '/loading',
    observers: [analyticsObserver],
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final userGroups = ref.read(userGroupsProvider);
      final location = state.matchedLocation;
      final isLoading = location == '/loading';
      final isLogin = location == '/login';
      final isGroupSetup = location == '/group-setup';

      if (authState.isLoading && !authState.hasValue) {
        return isLoading ? null : '/loading';
      }
      if (authState.hasError || authState.value == null) {
        return isLogin ? null : '/login';
      }
      if (userGroups.isLoading && !userGroups.hasValue) {
        return isLoading ? null : '/loading';
      }
      if ((userGroups.hasError && !userGroups.hasValue) ||
          (userGroups.hasValue && (userGroups.value?.isEmpty ?? true))) {
        return isGroupSetup ? null : '/group-setup';
      }
      return (isLoading || isLogin || isGroupSetup) ? '/shopping' : null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const _LoadingPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/group-setup',
        builder: (context, state) => const GroupSetupPage(),
      ),
      GoRoute(
        path: '/shopping',
        builder: (context, state) =>
            const MainScaffold(currentIndex: 0, child: ShoppingPage()),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const MainScaffold(currentIndex: 1, child: SettingsPage()),
      ),
      GoRoute(
        path: '/purchase-history',
        builder: (context, state) => const PurchaseHistoryPage(),
      ),
      GoRoute(
        path: '/group-details',
        builder: (context, state) => const GroupDetailsPage(),
      ),
      GoRoute(
        path: '/group-details/:groupId',
        builder: (context, state) =>
            GroupDetailsPage(groupId: state.pathParameters['groupId']),
      ),
      GoRoute(
        path: '/group-details/:groupId/categories',
        builder: (context, state) =>
            CategoryManagementPage(groupId: state.pathParameters['groupId']!),
      ),
    ],
  );

  ref.listen(authStateProvider, (_, _) => router.refresh());
  ref.listen(userGroupsProvider, (_, _) => router.refresh());

  ref.onDispose(router.dispose);
  return router;
});

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Katte', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
