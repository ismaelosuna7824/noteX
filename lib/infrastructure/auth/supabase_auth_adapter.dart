import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/repositories/auth_repository.dart'
    show AuthRepository, GoogleSignInCancelledException;

/// Supabase adapter for authentication.
///
/// Uses supabase_flutter which automatically persists sessions.
/// On desktop, opens the system browser for Google OAuth.
class SupabaseAuthAdapter implements AuthRepository {
  final SupabaseClient _client;

  final _authStateController = StreamController<bool>.broadcast();
  StreamSubscription<AuthState>? _authSubscription;

  /// Holds the local HTTP server waiting for the OAuth redirect.
  /// Closed when the user cancels sign-in.
  HttpServer? _pendingServer;

  /// Set to true by [cancelGoogleSignIn] so the error is not surfaced as a
  /// real auth failure.
  bool _signInCancelled = false;

  SupabaseAuthAdapter(this._client);

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

  /// Cancels an in-progress desktop Google sign-in by closing the local
  /// HTTP server. The [signInWithGoogle] Future will then throw
  /// [GoogleSignInCancelledException].
  @override
  Future<void> cancelGoogleSignIn() async {
    _signInCancelled = true;
    await _pendingServer?.close(force: true);
    _pendingServer = null;
  }

  Future<void> _signInDesktop() async {
    _signInCancelled = false;

    // 1. Pick a port and start a local HTTP server for the OAuth redirect.
    const int port = 54321;

    _log('Binding HTTP server on 127.0.0.1:$port ...');
    late final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } catch (e) {
      _log('ERROR binding port $port: $e');
      rethrow;
    }
    _log('Server bound successfully on port ${server.port}');
    _pendingServer = server;

    final redirectUri = 'http://localhost:$port/auth/callback';

    try {
      // 2. Get the OAuth URL from Supabase (includes PKCE code challenge)
      _log('Requesting OAuth URL from Supabase (redirectTo: $redirectUri)');
      final res = await _client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: redirectUri,
        queryParams: {'access_type': 'offline', 'prompt': 'consent'},
      );
      _log('OAuth URL obtained: ${res.url.substring(0, 80)}...');

      // 3. Open the URL in the system browser
      final url = Uri.parse(res.url);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open browser for Google Sign-In');
      }
      _log('Browser launched, waiting for callback...');

      // 4. Wait for the redirect callback (with 5-minute timeout).
      //    If the user cancels, [cancelGoogleSignIn] closes the server which
      //    causes server.first to throw — we catch it below.
      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('Sign-in timed out'),
      );

      _log('Callback received: ${request.uri}');
      _log('Request method: ${request.method}');
      _log('Query params: ${request.uri.queryParameters}');

      // 5. Extract the auth code from the callback URL
      final code = request.uri.queryParameters['code'];

      // Send a success page to the browser
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body style="font-family:system-ui;display:flex;'
          'justify-content:center;align-items:center;height:100vh;margin:0">'
          '<div style="text-align:center">'
          '<h2>Login successful!</h2>'
          '<p>You can close this tab and return to NoteX.</p>'
          '</div></body></html>',
        );
      await request.response.close();

      if (code == null || code.isEmpty) {
        _log('ERROR: No authorization code in callback params');
        throw Exception('No authorization code received');
      }

      // 6. Exchange the PKCE code for a Supabase session
      _log('Exchanging code for session...');
      await _client.auth.exchangeCodeForSession(code);
      _log('Session exchange successful — user authenticated');
    } catch (e) {
      _log('ERROR in OAuth flow: $e');
      // If the user cancelled, convert any exception into the canonical type.
      if (_signInCancelled) throw const GoogleSignInCancelledException();
      rethrow;
    } finally {
      await server.close(force: true);
      _pendingServer = null;
      _log('HTTP server closed');
    }
  }

  /// Writes a timestamped log line to stderr (visible in Terminal / Console.app
  /// even in release builds) and also appends to a log file in the system temp
  /// directory for easy retrieval.
  static void _log(String message) {
    final line = '[NoteX-Auth ${DateTime.now().toIso8601String()}] $message';
    // ignore: avoid_print
    print(line);
    try {
      final logFile = File(
        '${Directory.systemTemp.path}/notex_auth_debug.log',
      );
      logFile.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // Silently ignore file-write errors.
    }
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
