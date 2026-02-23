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

/// Port (interface) for checking application updates.
///
/// Infrastructure adapters implement this to check a remote source
/// (e.g. GitHub Releases) for newer versions.
abstract class UpdateService {
  /// Checks whether a newer version than [currentVersion] is available.
  ///
  /// Returns [UpdateInfo] if a newer release exists, or `null` if the app
  /// is up-to-date (or the check fails silently).
  Future<UpdateInfo?> checkForUpdate(String currentVersion);
}
