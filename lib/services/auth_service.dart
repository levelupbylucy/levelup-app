import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/level_up_models.dart';

class AuthService {
  AuthService({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  static final AuthService instance = AuthService();

  final GoogleSignIn _googleSignIn;
  bool _googleInitialized = false;

  bool get isFirebaseReady => !_isFlutterTest && Firebase.apps.isNotEmpty;

  AuthSession? currentSession() {
    if (!isFirebaseReady) return null;
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return _sessionFromUser(user, _providerFromFirebaseUser(user));
  }

  Stream<AuthSession?> authStateChanges() {
    if (!isFirebaseReady) return const Stream.empty();
    return firebase_auth.FirebaseAuth.instance.authStateChanges().map((user) {
      if (user == null) return null;
      return _sessionFromUser(user, _providerFromFirebaseUser(user));
    });
  }

  Future<AuthSession> signInWithGoogle() async {
    _ensureFirebaseReady();
    await _initializeGoogle();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw const AuthServiceException(
        'Google sign-in is not available on this platform yet.',
      );
    }

    final googleUser = await _googleSignIn.authenticate(
      scopeHint: const ['email'],
    );
    final googleAuth = googleUser.authentication;
    final credential = firebase_auth.GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    final result = await firebase_auth.FirebaseAuth.instance
        .signInWithCredential(credential);
    final user = result.user;
    if (user == null) {
      throw const AuthServiceException('Google sign-in did not return a user.');
    }
    return _sessionFromUser(user, AuthProvider.google);
  }

  Future<void> signOut() async {
    if (isFirebaseReady) {
      await firebase_auth.FirebaseAuth.instance.signOut();
    }
    if (_googleInitialized) {
      await _googleSignIn.signOut();
    }
  }

  Future<void> _initializeGoogle() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize();
    _googleInitialized = true;
  }

  void _ensureFirebaseReady() {
    if (!isFirebaseReady) {
      throw const AuthServiceException(
        'Firebase is not configured yet. Add GoogleService-Info.plist and run FlutterFire configuration before enabling sign-in.',
      );
    }
  }

  AuthProvider _providerFromFirebaseUser(firebase_auth.User user) {
    for (final info in user.providerData) {
      if (info.providerId == 'google.com') return AuthProvider.google;
    }
    return AuthProvider.google;
  }

  AuthSession _sessionFromUser(firebase_auth.User user, AuthProvider provider) {
    return AuthSession(
      userId: user.uid,
      provider: provider,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      photoUrl: user.photoURL ?? '',
    );
  }

  bool get _isFlutterTest {
    final binding = WidgetsBinding.instance;
    return binding.runtimeType.toString().contains('TestWidgetsFlutterBinding');
  }
}

class AuthServiceException implements Exception {
  const AuthServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
