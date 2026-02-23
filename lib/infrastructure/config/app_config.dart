/// Environment-based configuration for the application.
///
/// Supports different configurations for dev, staging, and production.
class AppConfig {
  final String environment;
  final String apiBaseUrl;
  final Duration autoSaveDebounce;
  final Duration syncInterval;
  final bool enableLogging;

  // Supabase
  final String supabaseUrl;
  final String supabaseAnonKey;

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
      supabaseUrl: 'https://dfkgixyerekdtjikmqez.supabase.co',
      supabaseAnonKey: 'sb_publishable_uIlbvvZkbe7SZ8zUq0UVCA_T25wZMAf',
    );
  }

  /// Production configuration.
  factory AppConfig.production() {
    return const AppConfig(
      environment: 'production',
      apiBaseUrl: 'https://api.notex.app',
      enableLogging: false,
      supabaseUrl: 'https://dfkgixyerekdtjikmqez.supabase.co',
      supabaseAnonKey: 'sb_publishable_uIlbvvZkbe7SZ8zUq0UVCA_T25wZMAf',
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
  static const String currentVersion = '1.0.0';

  static const String githubOwner = 'ismaelosuna7824';
  static const String githubRepo = 'noteX';

  /// GitHub API endpoint for the latest release.
  static String get githubLatestReleaseUrl =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
}
