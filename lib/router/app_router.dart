import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/groups/group_providers.dart';
import '../features/groups/presentation/group_details_page.dart';
import '../features/groups/presentation/group_setup_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shopping/presentation/purchase_history_page.dart';
import '../features/shopping/presentation/shopping_page.dart';
import '../shared/main_scaffold.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final userGroups = ref.watch(userGroupsProvider);
  final router = GoRouter(
    initialLocation: '/loading',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isLoading = location == '/loading';
      final isLogin = location == '/login';
      final isGroupSetup = location == '/group-setup';

      if (authState.isLoading) {
        return isLoading ? null : '/loading';
      }
      if (authState.hasError || authState.value == null) {
        return isLogin ? null : '/login';
      }
      if (userGroups.isLoading) {
        return isLoading ? null : '/loading';
      }
      if (userGroups.hasError || (userGroups.value?.isEmpty ?? true)) {
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
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Katte'),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
