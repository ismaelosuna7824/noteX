import 'dart:async';

import '../../domain/repositories/auth_repository.dart';

/// Stub adapter for Firebase Authentication.
///
/// This is architecture-ready — swap this implementation with a real
/// Firebase Auth adapter when you configure your Firebase project.
class FirebaseAuthAdapter implements AuthRepository {
  bool _isAuthenticated = false;
  String? _userId;
  String? _displayName;
  String? _avatarUrl;

  final _authStateController = StreamController<bool>.broadcast();

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get currentUserId => _userId;

  @override
  String? get displayName => _displayName;

  @override
  String? get avatarUrl => _avatarUrl;

  @override
  Future<void> signInWithGoogle() async {
    // TODO: Replace with real Firebase Auth implementation:
    // final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    // final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;
    // final credential = GoogleAuthProvider.credential(
    //   accessToken: googleAuth?.accessToken,
    //   idToken: googleAuth?.idToken,
    // );
    // await FirebaseAuth.instance.signInWithCredential(credential);

    // Stub: simulate successful sign-in
    _isAuthenticated = true;
    _userId = 'stub-user-id';
    _displayName = 'User';
    _avatarUrl = null;
    _authStateController.add(true);
  }

  @override
  Future<void> signOut() async {
    // TODO: Replace with FirebaseAuth.instance.signOut();
    _isAuthenticated = false;
    _userId = null;
    _displayName = null;
    _avatarUrl = null;
    _authStateController.add(false);
  }

  @override
  Stream<bool> get authStateChanges => _authStateController.stream;

  void dispose() {
    _authStateController.close();
  }
}
