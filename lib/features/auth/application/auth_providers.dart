import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/application/notification_service_provider.dart';
import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return FirebaseAuthService();
});

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<void>>(AuthController.new);

class AuthController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> signInWithGoogle() {
    return _run(ref.read(authServiceProvider).signInWithGoogle);
  }

  Future<void> signOut() {
    return _run(() async {
      final user = ref.read(authStateProvider).value;
      if (user != null) {
        await ref.read(notificationServiceProvider).unregisterForUser(user);
      }
      await ref.read(authServiceProvider).signOut();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
    } on AuthCancelledException {
      state = const AsyncData(null);
    } on Object catch (error, stackTrace) {
      final safeError = error is AuthFlowException
          ? error
          : const AuthFlowException('処理を完了できませんでした。もう一度お試しください。');
      state = AsyncError(safeError, stackTrace);
    }
  }
}
