import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katte/features/auth/application/apple_reauthentication.dart';

void main() {
  test('hashAppleNonce creates the expected SHA-256 value', () {
    expect(
      hashAppleNonce('katte-apple-reauth'),
      '741b392951185b81049b2312799817dc83a5b0132c69978c4d8e4f513d98b5d2',
    );
  });

  test('Apple Firebase credential keeps the ID token and raw nonce paired', () {
    final credential = createAppleReauthenticationCredential(
      identityToken: 'identity-token',
      rawNonce: 'raw-nonce',
    );

    expect(credential.providerId, AppleAuthProvider.PROVIDER_ID);
    expect(credential.signInMethod, AppleAuthProvider.APPLE_SIGN_IN_METHOD);
    expect(credential.idToken, 'identity-token');
    expect(credential.rawNonce, 'raw-nonce');
    expect(credential.appleFullPersonName?.givenName, isNull);
    expect(credential.appleFullPersonName?.familyName, isNull);
  });
}
