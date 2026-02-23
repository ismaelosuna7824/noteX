/// Information about an available application update.
class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;
  final bool isMandatory;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    this.isMandatory = false,
  });
}

/// Port (interface) for checking and applying application updates.
///
/// Infrastructure adapters implement this to check a remote source
/// (e.g. GitHub Releases) for newer versions and apply them in-place.
abstract class UpdateService {
  /// Checks whether a newer version than [currentVersion] is available.
  ///
  /// Returns [UpdateInfo] if a newer release exists, or `null` if the app
  /// is up-to-date (or the check fails silently).
  Future<UpdateInfo?> checkForUpdate(String currentVersion);

  /// Downloads the update installer and launches it silently to upgrade
  /// the app in-place. [onProgress] receives values from 0.0 to 1.0.
  ///
  /// On Windows this downloads the Inno Setup installer and runs it with
  /// `/VERYSILENT`. On other platforms falls back to opening the browser.
  Future<void> applyUpdate(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  });
}
