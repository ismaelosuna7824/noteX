import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Metadata for a remotely-hosted video background.
class RemoteBackground {
  final String name;
  final String filename;

  const RemoteBackground({required this.name, required this.filename});

  /// The GitHub Releases download URI (path segments auto-encode spaces/special chars).
  Uri get downloadUri => Uri(
        scheme: 'https',
        host: 'github.com',
        pathSegments: [
          'ismaelosuna7824',
          'noteX',
          'releases',
          'download',
          'backgrounds-v1',
          filename,
        ],
      );

  /// Bundled asset path for the pre-generated thumbnail JPEG.
  /// Matches the slug logic in scripts/generate_video_thumbnails.py.
  /// Falls back gracefully if the thumbnail doesn't exist yet.
  String get thumbnailAsset {
    final slug = filename
        .replaceAll(RegExp(r'\.[^.]+$'), '')      // remove extension
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_') // non-alphanum → _
        .replaceAll(RegExp(r'^_+|_+$'), '');        // trim leading/trailing _
    return 'assets/thumbnails/${slug}_thumb.jpg';
  }
}

/// Downloads and caches remote video backgrounds in the app support directory.
///
/// Cache location:
///   Windows  → %APPDATA%\notex\backgrounds\
///   macOS    → ~/Library/Application Support/notex/backgrounds/
///   Linux    → ~/.local/share/notex/backgrounds/
class BackgroundDownloader {
  BackgroundDownloader._();

  /// Minimum file size (512 KB) to consider a cached file valid.
  /// Prevents treating 404 HTML pages saved as files as real videos.
  static const int _minValidBytes = 512 * 1024;

  // ── Internal ────────────────────────────────────────────────────────────────

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'backgrounds'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Absolute local path for [filename] in the cache directory.
  static Future<String> localPath(String filename) async =>
      p.join((await _dir()).path, filename);

  /// Whether [filename] exists in the local cache AND is a valid video
  /// (size ≥ 512 KB — rules out HTML error pages saved by failed downloads).
  static Future<bool> isDownloaded(String filename) async {
    final f = File(await localPath(filename));
    if (!f.existsSync()) return false;
    return f.lengthSync() >= _minValidBytes;
  }

  /// Deletes [filename] from cache if it exists but is too small to be valid.
  /// Call this on startup or before retrying a failed download.
  static Future<void> deleteIfCorrupt(String filename) async {
    final f = File(await localPath(filename));
    if (f.existsSync() && f.lengthSync() < _minValidBytes) {
      await f.delete();
    }
  }

  /// Downloads [bg] to the local cache with streaming progress.
  ///
  /// Returns the local path on success, or `null` on any error
  /// (network failure, HTTP error status, redirect to HTML, etc.).
  static Future<String?> download(
    RemoteBackground bg, {
    required void Function(double progress) onProgress,
  }) async {
    final dest = await localPath(bg.filename);
    final tmp = '$dest.tmp';

    // Clean up any leftover corrupt file before starting
    await deleteIfCorrupt(bg.filename);

    try {
      final client = http.Client();
      Uri uri = bg.downloadUri;
      http.StreamedResponse? finalResponse;

      // Follow redirects manually (GitHub releases redirect to
      // objects.githubusercontent.com before serving the file).
      for (int i = 0; i < 8; i++) {
        final res = await client.send(http.Request('GET', uri));
        if (res.statusCode == 301 ||
            res.statusCode == 302 ||
            res.statusCode == 307 ||
            res.statusCode == 308) {
          final location = res.headers['location'];
          await res.stream.drain<void>();
          if (location == null) break;
          uri = Uri.parse(location);
          continue;
        }
        finalResponse = res;
        break;
      }

      if (finalResponse == null ||
          finalResponse.statusCode < 200 ||
          finalResponse.statusCode >= 300) {
        client.close();
        return null;
      }

      final total = finalResponse.contentLength ?? -1;
      int received = 0;

      final sink = File(tmp).openWrite();
      await for (final chunk in finalResponse.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      client.close();

      // Validate size before promoting to final path
      final tmpFile = File(tmp);
      if (tmpFile.lengthSync() < _minValidBytes) {
        await tmpFile.delete();
        return null;
      }

      // Atomic rename: avoids partial files being used
      await tmpFile.rename(dest);
      return dest;
    } catch (_) {
      try {
        await File(tmp).delete();
      } catch (_) {}
      return null;
    }
  }

  /// Removes a cached video from local storage.
  static Future<void> delete(String filename) async {
    final f = File(await localPath(filename));
    if (await f.exists()) await f.delete();
  }
}
