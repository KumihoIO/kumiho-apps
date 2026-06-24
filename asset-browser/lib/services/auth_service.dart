import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Authentication service for Kumiho Browser
///
/// Uses Firebase Authentication with popup-based login for desktop apps.
/// Supports Google, GitHub, and Email/Password authentication.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth;

  final FirebaseAuth? _auth;

  /// Stream of authentication state changes
  Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? Stream<User?>.value(null);

  /// Current authenticated user
  User? get currentUser => _auth?.currentUser;

  /// Whether the user is currently signed in
  bool get isSignedIn => currentUser != null;

  /// Get the current Firebase ID token for gRPC authentication
  ///
  /// Returns null if user is not signed in.
  /// Automatically refreshes token if expired.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return null;

    try {
      return await user.getIdToken(forceRefresh);
    } catch (e) {
      debugPrint('Error getting ID token: $e');
      return null;
    }
  }

  /// Sign in with Google using popup
  ///
  /// On desktop, this opens a webview for OAuth flow.
  Future<UserCredential> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthServiceException(
        code: 'firebase-not-configured',
        message: 'Firebase is not configured for this platform/build.',
      );
    }
    final googleProvider = GoogleAuthProvider();
    googleProvider.addScope('email');
    googleProvider.addScope('profile');

    if (kIsWeb) {
      return auth.signInWithPopup(googleProvider);
    }

    // Desktop: support depends on platform implementation.
    // Try it, and if unsupported, give a friendly actionable error.
    try {
      return await auth.signInWithPopup(googleProvider);
    } catch (e) {
      debugPrint('Google desktop sign-in failed: $e');
      throw const AuthServiceException(
        code: 'unsupported-desktop-oauth',
        message:
            'Google sign-in is not available in this Windows build. Use email/password in the app, or run the web version for Google sign-in.',
      );
    }
  }

  /// Sign in with GitHub using popup
  Future<UserCredential> signInWithGitHub() async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthServiceException(
        code: 'firebase-not-configured',
        message: 'Firebase is not configured for this platform/build.',
      );
    }
    final githubProvider = GithubAuthProvider();
    githubProvider.addScope('read:user');
    githubProvider.addScope('user:email');

    if (kIsWeb) {
      return auth.signInWithPopup(githubProvider);
    }

    // Desktop: support depends on platform implementation.
    try {
      return await auth.signInWithPopup(githubProvider);
    } catch (e) {
      debugPrint('GitHub desktop sign-in failed: $e');
      throw const AuthServiceException(
        code: 'unsupported-desktop-oauth',
        message:
            'GitHub sign-in is not available in this Windows build. Use email/password in the app, or run the web version for GitHub sign-in.',
      );
    }
  }

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthServiceException(
        code: 'firebase-not-configured',
        message: 'Firebase is not configured for this platform/build.',
      );
    }
    return auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Create a new account with email and password
  Future<UserCredential> createAccountWithEmail(
    String email,
    String password,
  ) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthServiceException(
        code: 'firebase-not-configured',
        message: 'Firebase is not configured for this platform/build.',
      );
    }
    return auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthServiceException(
        code: 'firebase-not-configured',
        message: 'Firebase is not configured for this platform/build.',
      );
    }
    await auth.sendPasswordResetEmail(email: email);
  }

  /// Sign out the current user
  Future<void> signOut() async {
    final auth = _auth;
    if (auth == null) return;
    await auth.signOut();
  }

  /// Delete the current user account
  ///
  /// This is a destructive action and cannot be undone.
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user != null) {
      await user.delete();
    }
  }

  /// Re-authenticate the user (required before sensitive operations)
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthServiceException(
        code: 'no-user',
        message: 'No user is currently signed in',
      );
    }
    return user.reauthenticateWithCredential(credential);
  }
}

/// Custom exception for app-level auth errors.
///
/// Use this for expected conditions (e.g. Firebase disabled on desktop), while
/// allowing Firebase SDK exceptions to pass through untouched.
class AuthServiceException implements Exception {
  const AuthServiceException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'AuthServiceException($code): $message';
}
