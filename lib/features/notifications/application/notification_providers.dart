import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../services/notification_service.dart';
import 'notification_service_provider.dart';

final notificationRegistrationProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return;
  }
  try {
    await ref.watch(notificationServiceProvider).registerForUser(user);
  } on Object catch (error, stackTrace) {
    debugPrint('Notification registration failed: $error\n$stackTrace');
  }
});

final notificationTapProvider = StreamProvider<NotificationTap>((ref) {
  return ref.watch(notificationServiceProvider).notificationTaps;
});
