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

  // Google OAuth (for desktop_webview_auth)
  final String googleClientId;
  final String googleClientSecret;

  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.autoSaveDebounce = const Duration(milliseconds: 800),
    this.syncInterval = const Duration(minutes: 5),
    this.enableLogging = true,
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
    this.googleClientId = '',
    this.googleClientSecret = '',
  });

  /// Development configuration.
  factory AppConfig.development() {
    return const AppConfig(
      environment: 'development',
      apiBaseUrl: 'http://localhost:8080/api',
      enableLogging: true,
      // TODO: Replace with your Supabase project credentials
      supabaseUrl: 'https://dfkgixyerekdtjikmqez.supabase.co',
      supabaseAnonKey: 'sb_publishable_uIlbvvZkbe7SZ8zUq0UVCA_T25wZMAf',
      googleClientId: '791820780526-7qbun5ap0nho5mgce33p30lqjocs9qs5.apps.googleusercontent.com',
      googleClientSecret: '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',
    );
  }

  /// Production configuration.
  factory AppConfig.production() {
    return const AppConfig(
      environment: 'production',
      apiBaseUrl: 'https://api.notex.app',
      enableLogging: false,
      // TODO: Replace with your production Supabase credentials
      supabaseUrl: 'https://dfkgixyerekdtjikmqez.supabase.co',
      supabaseAnonKey: 'sb_publishable_uIlbvvZkbe7SZ8zUq0UVCA_T25wZMAf',
      googleClientId: '791820780526-7qbun5ap0nho5mgce33p30lqjocs9qs5.apps.googleusercontent.com',
      googleClientSecret: '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',
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
}
