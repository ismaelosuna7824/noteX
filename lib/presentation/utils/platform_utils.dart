import 'dart:io' show Platform;

/// Whether the app is running on a desktop platform (Windows, macOS, Linux).
bool get kIsDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Whether the app is running on a mobile platform (Android, iOS).
bool get kIsMobile => Platform.isAndroid || Platform.isIOS;
