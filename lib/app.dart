import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/notifications/application/notification_providers.dart';
import 'features/monitoring/monitoring_providers.dart';
import 'router/app_router.dart';

class KatteApp extends ConsumerWidget {
  const KatteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    ref.watch(crashUserSyncProvider);
    ref.watch(notificationRegistrationProvider);
    ref.listen(notificationTapProvider, (previous, next) {
      next.whenData((_) => router.go('/shopping'));
    });

    return MaterialApp.router(
      title: 'Katte',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3B9C8F),
    brightness: brightness,
  );
  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
  final textTheme = GoogleFonts.notoSansJpTextTheme(baseTheme.textTheme);

  return baseTheme.copyWith(
    textTheme: textTheme.copyWith(
      displaySmall: textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.45,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.6),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.6),
      bodySmall: textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.5),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
