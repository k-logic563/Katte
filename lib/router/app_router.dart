import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shopping/presentation/shopping_page.dart';
import '../shared/main_scaffold.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final router = GoRouter(
    initialLocation: '/loading',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isLoading = location == '/loading';
      final isLogin = location == '/login';

      return switch (authState) {
        AsyncLoading() => isLoading ? null : '/loading',
        AsyncError() => isLogin ? null : '/login',
        AsyncData(value: null) => isLogin ? null : '/login',
        AsyncData() => (isLoading || isLogin) ? '/shopping' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const _LoadingPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
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
