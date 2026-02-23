/// Thrown when the user explicitly cancels a Google Sign-In flow.
class GoogleSignInCancelledException implements Exception {
  const GoogleSignInCancelledException();
}

/// Port (interface) for authentication operations.
///
/// The domain only knows about this contract — not Supabase or any provider.
abstract class AuthRepository {
  /// Restore a persisted session from previous launch.
  Future<void> initialize();

  /// Whether the user is currently authenticated.
  bool get isAuthenticated;

  /// The current user's unique identifier, or null if not authenticated.
  String? get currentUserId;

  /// The current user's display name.
  String? get displayName;

  /// The current user's avatar URL.
  String? get avatarUrl;

  /// Sign in with Google (OAuth flow).
  Future<void> signInWithGoogle();

  /// Cancel an in-progress Google Sign-In (e.g. user closed the browser).
  /// Throws [GoogleSignInCancelledException] to the awaiting [signInWithGoogle] caller.
  Future<void> cancelGoogleSignIn();

  /// Sign up with Email and Password.
  Future<void> signUpWithEmail(String email, String password);

  /// Sign in with Email and Password.
  Future<void> signInWithEmail(String email, String password);

  /// Sign out. Returns to local-only mode.
  Future<void> signOut();

  /// Get the current access token for API calls.
  Future<String?> getAccessToken();

  /// Stream of authentication state changes.
  Stream<bool> get authStateChanges;
}
