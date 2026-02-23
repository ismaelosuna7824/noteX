import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;

import '../../domain/services/update_service.dart';
import '../config/app_config.dart';

/// Checks for app updates via GitHub Releases API.
///
/// Fetches the latest release from the configured GitHub repo, compares
/// the tag version against the running app version, and returns platform-
/// specific download info when a newer release is available.
class GitHubUpdateAdapter implements UpdateService {
  @override
  Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    try {
      final response = await http
          .get(
            Uri.parse(AppConfig.githubLatestReleaseUrl),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Parse version from tag (strip leading "v" if present)
      final tagName = data['tag_name'] as String? ?? '';
      final remoteVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;

      if (!_isNewer(remoteVersion, currentVersion)) return null;

      // Find the download URL for the current platform
      final downloadUrl = _platformDownloadUrl(data);
      if (downloadUrl == null) return null;

      return UpdateInfo(
        version: remoteVersion,
        downloadUrl: downloadUrl,
        releaseNotes: (data['body'] as String?) ?? '',
        publishedAt: DateTime.tryParse(data['published_at'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      // Network errors, timeouts, JSON parse errors — fail silently.
      return null;
    }
  }

  /// Returns `true` when [remote] is a higher semver than [local].
  static bool _isNewer(String remote, String local) {
    final r = _parseSemver(remote);
    final l = _parseSemver(local);
    if (r == null || l == null) return false;

    for (var i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  /// Parses a "major.minor.patch" string into a list of three ints.
  static List<int>? _parseSemver(String version) {
    final parts = version.split('.');
    if (parts.length < 3) return null;
    try {
      return parts.take(3).map(int.parse).toList();
    } catch (_) {
      return null;
    }
  }

  /// Searches the release assets for a file matching the current OS.
  ///
  /// Convention:
  /// - Windows: asset name contains "windows" (e.g. NoteX-windows.zip)
  /// - macOS:   asset name contains "macos"   (e.g. NoteX-macos.zip)
  /// - Linux:   asset name contains "linux"   (e.g. NoteX-linux.tar.gz)
  static String? _platformDownloadUrl(Map<String, dynamic> release) {
    final assets = release['assets'] as List<dynamic>? ?? [];

    String keyword;
    if (Platform.isWindows) {
      keyword = 'windows';
    } else if (Platform.isMacOS) {
      keyword = 'macos';
    } else if (Platform.isLinux) {
      keyword = 'linux';
    } else {
      return null;
    }

    for (final asset in assets) {
      final name =
          ((asset as Map<String, dynamic>)['name'] as String? ?? '')
              .toLowerCase();
      if (name.contains(keyword)) {
        return asset['browser_download_url'] as String?;
      }
    }

    // Fallback: link to the release page itself so the user can choose
    return release['html_url'] as String?;
  }
}
