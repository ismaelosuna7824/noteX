import '../../domain/services/update_service.dart';
import '../../infrastructure/config/app_config.dart';

/// Checks whether a newer version of the app is available.
class CheckForUpdateUseCase {
  final UpdateService _updateService;

  CheckForUpdateUseCase(this._updateService);

  /// Returns [UpdateInfo] when an update exists, or `null` when up-to-date.
  Future<UpdateInfo?> execute() {
    return _updateService.checkForUpdate(AppConfig.currentVersion);
  }
}
