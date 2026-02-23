import 'dart:convert';
import 'dart:io'
    show Directory, File, Platform, Process, ProcessStartMode, exit, pid;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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

  @override
  Future<void> applyUpdate(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    if (Platform.isWindows) {
      await _applyWindows(update, onProgress);
    } else if (Platform.isMacOS) {
      await _applyMacOS(update, onProgress);
    } else {
      // Linux / other: fall back to opening the browser
      final uri = Uri.parse(update.downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // ── Windows: silent Inno Setup installer ──────────────────────────────

  Future<void> _applyWindows(
    UpdateInfo update,
    void Function(double)? onProgress,
  ) async {
    final installerPath =
        '${Directory.systemTemp.path}/NoteX-windows-setup.exe';

    await _downloadFile(update.downloadUrl, installerPath, onProgress);

    // Launch the installer silently — Inno Setup will close the running
    // app (via CloseApplications=yes) and restart it after upgrading.
    await Process.start(
      installerPath,
      [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  // ── macOS: mount DMG, replace .app bundle, relaunch ───────────────────

  Future<void> _applyMacOS(
    UpdateInfo update,
    void Function(double)? onProgress,
  ) async {
    final dmgPath = '${Directory.systemTemp.path}/NoteX-macos.dmg';

    await _downloadFile(update.downloadUrl, dmgPath, onProgress);

    // Resolve the current .app bundle path from the running executable.
    // Platform.resolvedExecutable → /Applications/notex.app/Contents/MacOS/notex
    final executable = Platform.resolvedExecutable;
    final appSuffix = '.app/';
    final appEndIndex = executable.indexOf(appSuffix);
    if (appEndIndex < 0) {
      throw Exception('Cannot determine .app bundle path');
    }
    final appBundlePath = executable.substring(0, appEndIndex + 4); // includes ".app"
    final appDir = File(appBundlePath).parent.path;

    // Create an update script that runs after the app exits.
    // macOS keeps the binary in memory after the .app is deleted, so this is safe.
    final scriptPath = '${Directory.systemTemp.path}/notex_update.sh';
    final currentPid = pid;

    final script = '''#!/bin/bash
# Wait for the current process to exit
while kill -0 $currentPid 2>/dev/null; do sleep 0.3; done

# Mount the DMG
MOUNT_OUTPUT=\$(hdiutil attach "$dmgPath" -nobrowse -readonly 2>&1)
MOUNT_POINT=\$(echo "\$MOUNT_OUTPUT" | grep -oE '/Volumes/[^\\t\\n]+' | head -1)

if [ -z "\$MOUNT_POINT" ]; then
  rm -f "$dmgPath" "$scriptPath"
  exit 1
fi

# Find the .app inside the mounted volume
APP_FOUND=\$(ls "\$MOUNT_POINT" | grep '\\.app\$' | head -1)

if [ -z "\$APP_FOUND" ]; then
  hdiutil detach "\$MOUNT_POINT" -quiet
  rm -f "$dmgPath" "$scriptPath"
  exit 1
fi

TARGET="$appDir/\$APP_FOUND"

# Check if we can write directly; if not, elevate via osascript
if [ -w "$appDir" ]; then
  rm -rf "\$TARGET"
  cp -Rf "\$MOUNT_POINT/\$APP_FOUND" "$appDir/"
  xattr -cr "\$TARGET"
else
  osascript -e "do shell script \\"rm -rf '\$TARGET' && cp -Rf '\$MOUNT_POINT/\$APP_FOUND' '$appDir/' && xattr -cr '\$TARGET'\\" with administrator privileges"
fi

# Unmount and clean up
hdiutil detach "\$MOUNT_POINT" -quiet
rm -f "$dmgPath"

# Relaunch
open "\$TARGET"

# Self-delete
rm -f "$scriptPath"
''';

    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);

    // Launch the update script detached so it outlives this process
    await Process.start(
      '/bin/bash',
      [scriptPath],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  // ── Shared: streaming download with progress ──────────────────────────

  Future<void> _downloadFile(
    String url,
    String destPath,
    void Function(double)? onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final streamedResponse = await request.send().timeout(
      const Duration(minutes: 5),
    );

    if (streamedResponse.statusCode != 200) {
      throw Exception('Download failed: HTTP ${streamedResponse.statusCode}');
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    var receivedBytes = 0;
    final sink = File(destPath).openWrite();

    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(receivedBytes / totalBytes);
      }
    }
    await sink.close();
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
  /// - Windows: asset name contains "windows" (e.g. NoteX-windows-setup.exe)
  /// - macOS:   asset name contains "macos"   (e.g. NoteX-macos.dmg)
  /// - Linux:   asset name contains "linux"   (e.g. NoteX-linux.deb)
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
