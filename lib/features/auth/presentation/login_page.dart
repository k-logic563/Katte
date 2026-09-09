import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                    const SizedBox(height: 16),
                    Text(
                      '家族の「買っといて」を、\nもっと気軽に。',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: SizedBox(
                        width: double.infinity,
                        child: _LoginButtons(
                          isLoading: isLoading,
                          onGooglePressed: ref
                              .read(authControllerProvider.notifier)
                              .signInWithGoogle,
                          onApplePressed: ref
                              .read(authControllerProvider.notifier)
                              .signInWithApple,
                        ),
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

const _loginCardHeight = 64.0;
const _loginCardRadius = BorderRadius.all(Radius.circular(12));
const _loginCardBorderColor = Color(0xFF747775);

class _LoginButtons extends StatelessWidget {
  const _LoginButtons({
    required this.isLoading,
    required this.onGooglePressed,
    required this.onApplePressed,
  });

  final bool isLoading;
  final VoidCallback onGooglePressed;
  final VoidCallback onApplePressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '続行する方法を選択',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _GoogleSignInCard(
                onPressed: isLoading ? null : onGooglePressed,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _AppleSignInCard(
                onPressed: isLoading ? null : onApplePressed,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 32,
          child: Center(
            child: isLoading
                ? Semantics(
                    liveRegion: true,
                    label: 'ログインしています',
                    child: const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _GoogleSignInCard extends StatelessWidget {
  const _GoogleSignInCard({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _SocialLoginCard(
      buttonKey: const Key('google-login-button'),
      onPressed: onPressed,
      semanticsLabel: 'Googleで続ける',
      icon: Image.asset(
        'assets/branding/google_g.png',
        key: const Key('google-logo'),
        height: 24,
        excludeFromSemantics: true,
      ),
    );
  }
}

class _AppleSignInCard extends StatelessWidget {
  const _AppleSignInCard({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _SocialLoginCard(
      buttonKey: const Key('apple-login-button'),
      onPressed: onPressed,
      semanticsLabel: 'Appleでサインイン',
      icon: const SizedBox(
        key: Key('apple-logo'),
        width: 24 * (25 / 31),
        height: 24,
        child: CustomPaint(painter: AppleLogoPainter(color: Colors.black)),
      ),
    );
  }
}

class _SocialLoginCard extends StatelessWidget {
  const _SocialLoginCard({
    required this.buttonKey,
    required this.onPressed,
    required this.semanticsLabel,
    required this.icon,
  });

  final Key buttonKey;
  final VoidCallback? onPressed;
  final String semanticsLabel;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: semanticsLabel,
          child: SizedBox(
            height: _loginCardHeight,
            child: OutlinedButton(
              key: buttonKey,
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFF2F2F2),
                side: const BorderSide(color: _loginCardBorderColor),
                shape: const RoundedRectangleBorder(
                  borderRadius: _loginCardRadius,
                ),
                padding: EdgeInsets.zero,
              ),
              child: Opacity(
                opacity: onPressed == null ? 0.38 : 1,
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
