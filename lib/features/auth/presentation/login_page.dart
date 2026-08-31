import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_providers.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAction = ref.watch(authControllerProvider);
    final isLoading = authAction.isLoading;

    ref.listen(authControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, stackTrace) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('ログインできませんでした。もう一度お試しください。')),
            );
        },
      );
    });

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 64,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/branding/app_icon.png',
                        key: const Key('brand-app-icon'),
                        width: 88,
                        height: 88,
                        semanticLabel: 'Katte',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Katte',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '家族の「買っといて」を、\nリアルタイムで共有。',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const Key('google-login-button'),
                        onPressed: isLoading
                            ? null
                            : ref
                                  .read(authControllerProvider.notifier)
                                  .signInWithGoogle,
                        child: isLoading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Googleで続ける'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
