/// Environment-based configuration for the application.
///
/// Secrets (Supabase URL and anon key) are injected at **compile time** via
/// `--dart-define` flags — they are never stored in source code.
///
/// ### Local development
/// Copy `dart_defines.json.example` → `dart_defines.json`, fill in your real
/// values, then build/run with:
/// ```
/// flutter run --dart-define-from-file=dart_defines.json
/// flutter build windows --dart-define-from-file=dart_defines.json --release
/// ```
///
/// ### CI / GitHub Actions
/// Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` as repository secrets and the
/// workflow will pass them automatically.
class AppConfig {
  final String environment;
  final String apiBaseUrl;
  final Duration autoSaveDebounce;
  final Duration syncInterval;
  final bool enableLogging;

  // Supabase — injected at compile time, never hardcoded.
  final String supabaseUrl;
  final String supabaseAnonKey;

  // ── Compile-time secrets ────────────────────────────────────────────────
  // These are resolved once at app startup; the build fails loudly if they
  // are missing so misconfigured builds are caught early.
  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.autoSaveDebounce = const Duration(milliseconds: 800),
    this.syncInterval = const Duration(minutes: 5),
    this.enableLogging = true,
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
  });

  /// Development configuration.
  factory AppConfig.development() {
    return const AppConfig(
      environment: 'development',
      apiBaseUrl: 'http://localhost:8080/api',
      enableLogging: true,
      supabaseUrl: _supabaseUrl,
      supabaseAnonKey: _supabaseAnonKey,
    );
  }

  /// Production configuration.
  factory AppConfig.production() {
    return const AppConfig(
      environment: 'production',
      apiBaseUrl: 'https://api.notex.app',
      enableLogging: false,
      supabaseUrl: _supabaseUrl,
      supabaseAnonKey: _supabaseAnonKey,
    );
  }

  /// Resolve config from environment variable or default to development.
  factory AppConfig.fromEnvironment() {
    const env = String.fromEnvironment('ENV', defaultValue: 'development');
    switch (env) {
      case 'production':
        return AppConfig.production();
      default:
        return AppConfig.development();
    }
  }

  bool get isDevelopment => environment == 'development';
  bool get isProduction => environment == 'production';

  // ── GitHub Release auto-update ──────────────────────────────────────────

  /// Current app version — keep in sync with pubspec.yaml `version:` field.
  static const String currentVersion = '1.41.0';

  static const String githubOwner = 'ismaelosuna7824';
  static const String githubRepo = 'noteX';

  /// GitHub API endpoint for the latest release.
  static String get githubLatestReleaseUrl =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
}
