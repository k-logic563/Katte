import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

String hashAppleNonce(String rawNonce) {
  return sha256.convert(utf8.encode(rawNonce)).toString();
}

OAuthCredential createAppleReauthenticationCredential({
  required String identityToken,
  required String rawNonce,
}) {
  return AppleAuthProvider.credentialWithIDToken(
    identityToken,
    rawNonce,
    AppleFullPersonName(),
  );
}
