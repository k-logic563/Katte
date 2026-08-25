import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  Future<void> signOut();
}

class AuthCancelledException implements Exception {}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

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

AuthFlowException _friendlyAuthError(FirebaseAuthException error) {
  if (error.code == 'network-request-failed') {
    return const AuthFlowException('通信状態を確認して、もう一度お試しください。');
  }
  return const AuthFlowException('認証できませんでした。もう一度お試しください。');
}
