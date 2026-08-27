import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/notifications/application/notification_providers.dart';
import 'router/app_router.dart';

class KatteApp extends ConsumerWidget {
  const KatteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    ref.watch(notificationRegistrationProvider);
    ref.listen(notificationTapProvider, (previous, next) {
      next.whenData((_) => router.go('/shopping'));
    });
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.teal,
      scaffoldBackgroundColor: Colors.white,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
    );
    final notoSansJpTextTheme = GoogleFonts.notoSansJpTextTheme(
      baseTheme.textTheme,
    );

    return MaterialApp.router(
      title: 'Katte',
      theme: baseTheme.copyWith(
        textTheme: notoSansJpTextTheme.copyWith(
          displaySmall: notoSansJpTextTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
          headlineMedium: notoSansJpTextTheme.headlineMedium?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
          headlineSmall: notoSansJpTextTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          titleLarge: notoSansJpTextTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          titleMedium: notoSansJpTextTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
          titleSmall: notoSansJpTextTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: notoSansJpTextTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.6,
          ),
          bodyMedium: notoSansJpTextTheme.bodyMedium?.copyWith(height: 1.6),
          bodySmall: notoSansJpTextTheme.bodySmall?.copyWith(
            fontSize: 13,
            height: 1.5,
          ),
          labelLarge: notoSansJpTextTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
