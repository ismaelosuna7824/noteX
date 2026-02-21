/// Port (interface) for authentication operations.
///
/// The domain only knows about this contract — not Firebase or any provider.
abstract class AuthRepository {
  /// Whether the user is currently authenticated.
  bool get isAuthenticated;

  /// The current user's unique identifier, or null if not authenticated.
  String? get currentUserId;

  /// The current user's display name.
  String? get displayName;

  /// The current user's avatar URL.
  String? get avatarUrl;

  /// Sign in with Google.
  Future<void> signInWithGoogle();

  /// Sign out. Returns to local-only mode.
  Future<void> signOut();

  /// Stream of authentication state changes.
  Stream<bool> get authStateChanges;
}
