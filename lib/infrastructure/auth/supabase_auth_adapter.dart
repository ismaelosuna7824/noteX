import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:desktop_webview_auth/desktop_webview_auth.dart';
import 'package:desktop_webview_auth/google.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/auth_repository.dart';

/// Supabase adapter for authentication.
///
/// Uses supabase_flutter which automatically persists sessions.
/// On desktop, uses desktop_webview_auth for Google OAuth.
class SupabaseAuthAdapter implements AuthRepository {
  final SupabaseClient _client;
  final String _googleClientId;

  final _authStateController = StreamController<bool>.broadcast();
  StreamSubscription<AuthState>? _authSubscription;

  SupabaseAuthAdapter(this._client, {required String googleClientId})
      : _googleClientId = googleClientId;

  @override
  Future<void> initialize() async {
    // supabase_flutter auto-restores session from local storage
    // Listen to auth state changes and forward them
    _authSubscription = _client.auth.onAuthStateChange.listen((data) {
      _authStateController.add(data.session != null);
    });
  }

  @override
  bool get isAuthenticated => _client.auth.currentSession != null;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  String? get displayName {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final fullName = user.userMetadata?['full_name'] as String?;
    if (fullName != null && fullName.isNotEmpty) return fullName;
    // Fallback to email prefix for email/password auth users
    final email = user.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return email;
  }

  @override
  String? get avatarUrl =>
      _client.auth.currentUser?.userMetadata?['avatar_url'] as String?;

  @override
  Future<void> signInWithGoogle() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await _signInDesktop();
    } else {
      // Mobile: use native OAuth flow
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.notex://login-callback',
      );
    }
  }

  Future<void> _signInDesktop() async {
    // 1. Start a local server to listen for the OAuth redirect on the exact port configured in GCP
    final int port = 54321;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);

    // 2. Open the desktop webview with the loopback redirect URI matching the Supabase format
    final redirectUri = 'http://localhost:$port/auth/v1/callback';
    
    // We need to know the nonce to pass it to Supabase
    final String nonce = _client.auth.generateRawNonce();
    final String hashedNonce = sha256.convert(utf8.encode(nonce)).toString();

    final args = _CustomGoogleSignInArgs(
      clientId: _googleClientId,
      redirectUri: redirectUri,
      scope: 'email profile',
      nonce: hashedNonce, // Google requires the hashed version if PKCE, but Supabase checks the raw one later. Let's pass raw nonce here and to Supabase.
    );
    
    // We run the webview signin and the local server listen in parallel
    // The server will receive a request from the webview upon success
    AuthResult? authResult;
    
    try {
      final results = await Future.wait([
        DesktopWebviewAuth.signIn(args),
        server.first.then((HttpRequest request) async {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write('<html><body><strong>Login successful!</strong> You can close this window now.</body></html>');
          await request.response.close();
          return request.uri.toString();
        }).timeout(const Duration(minutes: 5)),
      ]);

      authResult = results[0] as AuthResult?;
      final callbackUrl = results[1] as String?;

      if (authResult == null && callbackUrl != null) {
        try {
          authResult = await args.authorizeFromCallback(callbackUrl);
        } catch (_) {}
      }
    } catch (e) {
      // Ignored
    } finally {
      await server.close(force: true);
    }

    if (authResult == null || (authResult.idToken == null && authResult.accessToken == null)) {
      throw Exception('Google Sign In cancelled or failed');
    }

    // Authenticate with Supabase using the received tokens.
    // Supabase requires the RAW nonce (if hashed during request, but GoogleSignInArgs just passes it as-is to the id_token).
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: authResult.idToken ?? authResult.accessToken!,
      accessToken: authResult.accessToken,
      nonce: hashedNonce, // Pass the same nonce we requested so Supabase can verify it
    );
  }

  @override
  Future<void> signUpWithEmail(String email, String password) async {
    await _client.auth.signUp(
      email: email,
      password: password,
    );
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<String?> getAccessToken() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;

    // Check if token is expired and refresh if needed
    if (session.isExpired) {
      final response = await _client.auth.refreshSession();
      return response.session?.accessToken;
    }
    return session.accessToken;
  }

  @override
  Stream<bool> get authStateChanges => _authStateController.stream;

  void dispose() {
    _authSubscription?.cancel();
    _authStateController.close();
  }
}

class _CustomGoogleSignInArgs extends GoogleSignInArgs {
  final String nonce;

  _CustomGoogleSignInArgs({
    required super.clientId,
    required super.redirectUri,
    super.scope,
    required this.nonce,
  });

  @override
  Map<String, String> buildQueryParameters() {
    final params = super.buildQueryParameters();
    // Overwrite the randomly generated nonce with our predictable one
    params['nonce'] = nonce;
    return params;
  }
}
