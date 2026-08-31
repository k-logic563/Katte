import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_providers.dart';
import 'monitoring_services.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return FirebaseAnalyticsService();
});

final crashReportingServiceProvider = Provider<CrashReportingService>((ref) {
  return FirebaseCrashReportingService();
});

final crashUserSyncProvider = Provider<void>((ref) {
  final userId = ref.watch(authStateProvider).value?.uid;
  unawaited(ref.read(crashReportingServiceProvider).setUserIdentifier(userId));
});
