/// Environment-based configuration for the application.
///
/// Supports different configurations for dev, staging, and production.
class AppConfig {
  final String environment;
  final String apiBaseUrl;
  final Duration autoSaveDebounce;
  final Duration syncInterval;
  final bool enableLogging;

  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.autoSaveDebounce = const Duration(milliseconds: 800),
    this.syncInterval = const Duration(minutes: 5),
    this.enableLogging = true,
  });

  /// Development configuration.
  factory AppConfig.development() {
    return const AppConfig(
      environment: 'development',
      apiBaseUrl: 'http://localhost:8080/api',
      enableLogging: true,
    );
  }

  /// Production configuration.
  factory AppConfig.production() {
    return const AppConfig(
      environment: 'production',
      apiBaseUrl: 'https://api.notex.app',
      enableLogging: false,
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
