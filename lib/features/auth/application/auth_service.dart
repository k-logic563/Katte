import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'apple_reauthentication.dart';

class AuthUser {
  const AuthUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
  });

  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;
}

abstract interface class AuthService {
  Stream<AuthUser?> authStateChanges();

  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  Future<void> deleteAccount();

  Future<void> signOut();
}

class AuthCancelledException implements Exception {}

class AccountDeletionBlockedException implements Exception {}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFunctions _functions;

  late final Future<void> _googleInitialization = _googleSignIn.initialize();

  @override
  Stream<AuthUser?> authStateChanges() {
    return _auth.authStateChanges().map((user) {
      if (user == null) {
        return null;
      }
      return AuthUser(
        uid: user.uid,
        displayName: user.displayName,
        email: user.email,
        photoUrl: user.photoURL,
      );
    });
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      await _googleInitialization;
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFlowException('Googleでログインできませんでした。');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        throw AuthCancelledException();
      }
      throw const AuthFlowException('Googleでログインできませんでした。');
    } on FirebaseAuthException catch (error) {
      throw _friendlyAuthError(error);
    }
  }

  @override
  Future<void> signInWithApple() async {
    try {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      await _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (error) {
      if (_isCancellation(error.code)) {
        throw AuthCancelledException();
      }
      throw _friendlyAuthError(error);
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFlowException('ログイン状態を確認できませんでした。');
    }

    try {
      // Blocked owner accounts are detected before Apple authorization is
      // revoked or a provider reauthentication UI is shown.
      await _functions
          .httpsCallable('checkAccountDeletion')
          .call<Map<String, dynamic>>();

      final providerIds = user.providerData
          .map((provider) => provider.providerId)
          .toSet();
      if (providerIds.contains(AppleAuthProvider.APPLE_SIGN_IN_METHOD)) {
        final rawNonce = generateNonce();
        final hashedNonce = hashAppleNonce(rawNonce);
        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: const [],
          nonce: hashedNonce,
        );

        final identityToken = appleCredential.identityToken;
        if (identityToken == null || identityToken.isEmpty) {
          throw const AuthFlowException('Appleとの認証を完了できませんでした。');
        }

        final authorizationCode = appleCredential.authorizationCode;
        if (authorizationCode.isEmpty) {
          throw const AuthFlowException('Appleとの認証を完了できませんでした。');
        }

        await user.reauthenticateWithCredential(
          createAppleReauthenticationCredential(
            identityToken: identityToken,
            rawNonce: rawNonce,
          ),
        );

        await _auth.revokeTokenWithAuthorizationCode(authorizationCode);
      } else if (providerIds.contains(
        GoogleAuthProvider.GOOGLE_SIGN_IN_METHOD,
      )) {
        await _googleInitialization;
        final account = await _googleSignIn.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw const AuthFlowException('Googleとの認証を完了できませんでした。');
        }
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
      } else {
        throw const AuthFlowException('このアカウントの再認証方法を確認できませんでした。');
      }

      await _functions
          .httpsCallable('deleteAccount')
          .call<Map<String, dynamic>>();

      await _auth.signOut();
      try {
        await _googleInitialization;
        await _googleSignIn.signOut();
      } on Object {
        // Firebase Authとserver dataは削除済みなのでGoogle側の失敗は無視する。
      }
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw AuthCancelledException();
      }
      throw const AuthFlowException('アカウントを削除できませんでした。');
    } on SignInWithAppleException {
      throw const AuthFlowException('アカウントを削除できませんでした。');
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        throw AuthCancelledException();
      }
      throw const AuthFlowException('アカウントを削除できませんでした。');
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'failed-precondition') {
        throw AccountDeletionBlockedException();
      }
      throw const AuthFlowException('アカウントを削除できませんでした。');
    } on FirebaseAuthException catch (error) {
      if (_isCancellation(error.code)) {
        throw AuthCancelledException();
      }
      throw const AuthFlowException('アカウントを削除できませんでした。');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw _friendlyAuthError(error);
    }

    try {
      await _googleInitialization;
      await _googleSignIn.signOut();
    } on Object {
      // Firebase Authのセッションは終了済みなので、Google側の失敗は無視する。
    }
  }
}

bool _isCancellation(String code) =>
    code == 'canceled' || code == 'web-context-canceled';

AuthFlowException _friendlyAuthError(FirebaseAuthException error) {
  if (error.code == 'network-request-failed') {
    return const AuthFlowException('通信状態を確認して、もう一度お試しください。');
  }
  return const AuthFlowException('認証できませんでした。もう一度お試しください。');
}
