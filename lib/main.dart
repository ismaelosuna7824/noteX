import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'injection.dart';
import 'infrastructure/config/app_config.dart';
import 'presentation/app.dart';
import 'presentation/state/app_state.dart';
import 'presentation/state/theme_state.dart';
import 'presentation/state/timer_state.dart';
import 'presentation/state/markdown_state.dart';
import 'presentation/state/reminder_state.dart';
import 'application/services/sync_engine.dart';
import 'domain/repositories/auth_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap image cache at 50 MB to prevent unbounded memory growth from
  // background images and gallery thumbnails.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;

  MediaKit.ensureInitialized();

  // 1. Initialize acrylic (transparent window effect) and window manager.
  // Retry once on failure — some Windows machines need a short delay on first
  // launch for the DWM / display subsystem to be ready.
  try {
    await Window.initialize();
  } catch (_) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await Window.initialize();
    } catch (_) {
      // Continue without acrylic — the app will still work.
    }
  }
  await windowManager.ensureInitialized();

  // 2. Initialize Supabase (auto-restores persisted session)
  final config = AppConfig.fromEnvironment();
  await Supabase.initialize(
    url: config.supabaseUrl,
    anonKey: config.supabaseAnonKey,
  );

  // 3. Setup dependency injection
  await setupDependencies();

  // 4. Initialize auth (restore session)
  final authRepo = getIt<AuthRepository>();
  await authRepo.initialize();

  // 5. Initialize app state (load notes, create daily note)
  final appState = getIt<AppState>();
  await appState.initialize();

  // Initialize timer state so HomePage has daily task stats immediately
  final timerState = getIt<TimerState>();
  await timerState.initialize();

  // Initialize markdown state
  final markdownState = getIt<MarkdownState>();
  await markdownState.initialize();

  // Initialize reminder state
  final reminderState = getIt<ReminderState>();
  await reminderState.initialize();

  // 6. Restore persisted theme settings
  final themeState = getIt<ThemeState>();
  await themeState.loadFromDisk();

  // 7. Start auto-sync and trigger initial sync if already logged in
  final syncEngine = getIt<SyncEngine>();
  syncEngine.startAutoSync();
  if (authRepo.isAuthenticated) {
    // Non-blocking initial sync
    syncEngine.sync();
  }

  // 8. Configure: transparent + frameless + centered
  // Clamp window size to fit the screen (accounts for display scaling).
  // Guard against ScreenRetriever failures on unusual Windows display configs
  // (multi-monitor, RDP, non-standard DPI, missing drivers).
  double screenW = 1920.0;
  double screenH = 1080.0;
  try {
    final display = await ScreenRetriever.instance.getPrimaryDisplay();
    final scale = (display.scaleFactor ?? 1.0).toDouble();
    // visibleSize excludes the taskbar; fall back to full size.
    final usable = display.visibleSize ?? display.size;
    final w = usable.width / scale;
    final h = usable.height / scale;
    // Sanity-check: values must be positive and reasonable.
    if (w > 0 && h > 0) {
      screenW = w;
      screenH = h;
    }
  } catch (_) {
    // Fallback values already set above.
  }
  const margin = 40.0;

  // Check if the app was closed in compact mode.
  final compactState = await WindowSizeStore.loadCompactState();
  final restoreCompact = compactState != null;

  double windowW;
  double windowH;
  double minW;
  double minH;

  // Whether we actually end up in compact mode (note may have been deleted).
  bool activeCompact = false;

  if (restoreCompact) {
    // Restore compact mode in AppState first — if the note was deleted
    // (e.g. empty-note cleanup on last close) this returns false and we
    // fall back to the normal window layout instead.
    final noteId = compactState['compact_note_id'] as String?;
    final noteFound = noteId != null && appState.restoreCompactMode(noteId);

    if (noteFound) {
      activeCompact = true;
      minW = 300.0;
      minH = 350.0;
      final compact = await WindowSizeStore.loadCompact();
      windowW = compact?['width'] ?? 400.0;
      windowH = compact?['height'] ?? 500.0;
    } else {
      // Note no longer exists — clear the stale compact state and open normally.
      await WindowSizeStore.saveCompactState(isCompact: false, noteId: null);
      minW = 900.0;
      minH = 600.0;
      final saved = await WindowSizeStore.load();
      final defaultW = saved?['width'] ?? 1280.0;
      final defaultH = saved?['height'] ?? 900.0;
      windowW = min(defaultW, screenW - margin).clamp(minW, screenW - margin);
      windowH = min(defaultH, screenH - margin).clamp(minH, screenH - margin);
    }
  } else {
    // Restore normal window size, falling back to 1280x900.
    minW = 900.0;
    minH = 600.0;
    final saved = await WindowSizeStore.load();
    final defaultW = saved?['width'] ?? 1280.0;
    final defaultH = saved?['height'] ?? 900.0;
    windowW = min(defaultW, screenW - margin).clamp(minW, screenW - margin);
    windowH = min(defaultH, screenH - margin).clamp(minH, screenH - margin);
  }

  final windowOptions = WindowOptions(
    size: Size(windowW, windowH),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  // waitUntilReadyToShow is intentionally NOT awaited —
  // it runs alongside runApp so rendering begins immediately.
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    try {
      await Window.setEffect(
        effect: WindowEffect.transparent,
        color: Colors.transparent,
      );
    } catch (_) {
      // Transparent effect unsupported — continue without it.
    }
    await windowManager.setAsFrameless();
    // Allow resizing and enforce a minimum window size on all platforms.
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(Size(minW, minH));
    if (activeCompact) {
      await windowManager.setAlwaysOnTop(true);
    }
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(NoteXApp(appState: appState, themeState: themeState));
}

/// Persists and restores window size across sessions.
class WindowSizeStore {
  static const _fileName = 'notex_window_size.json';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, double>?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return {
        'width': (json['width'] as num).toDouble(),
        'height': (json['height'] as num).toDouble(),
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(double width, double height) async {
    try {
      final file = await _file();
      Map<String, dynamic> json = {};
      if (await file.exists()) {
        json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
      json['width'] = width;
      json['height'] = height;
      await file.writeAsString(jsonEncode(json));
    } catch (_) {
      // Non-critical — silently ignore write failures.
    }
  }

  static Future<Map<String, double>?> loadCompact() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (!json.containsKey('compact_width')) return null;
      return {
        'width': (json['compact_width'] as num).toDouble(),
        'height': (json['compact_height'] as num).toDouble(),
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCompact(double width, double height) async {
    try {
      final file = await _file();
      Map<String, dynamic> json = {};
      if (await file.exists()) {
        json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
      json['compact_width'] = width;
      json['compact_height'] = height;
      await file.writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  /// Save whether the app was closed in compact mode (and which note).
  static Future<void> saveCompactState({
    required bool isCompact,
    String? noteId,
  }) async {
    try {
      final file = await _file();
      Map<String, dynamic> json = {};
      if (await file.exists()) {
        json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
      json['compact_mode'] = isCompact;
      json['compact_note_id'] = noteId;
      await file.writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  /// Load the compact mode state saved at last close.
  static Future<Map<String, dynamic>?> loadCompactState() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['compact_mode'] != true) return null;
      return {
        'compact_mode': true,
        'compact_note_id': json['compact_note_id'] as String?,
      };
    } catch (_) {
      return null;
    }
  }
}
