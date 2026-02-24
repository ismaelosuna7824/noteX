import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
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
  MediaKit.ensureInitialized();

  // 1. Initialize acrylic (transparent window effect) and window manager
  await Window.initialize();
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
  const windowOptions = WindowOptions(
    size: Size(1280, 900),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  // waitUntilReadyToShow is intentionally NOT awaited —
  // it runs alongside runApp so rendering begins immediately.
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await Window.setEffect(
      effect: WindowEffect.transparent,
      color: Colors.transparent,
    );
    await windowManager.setAsFrameless();
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    NoteXApp(
      appState: appState,
      themeState: themeState,
    ),
  );
}
