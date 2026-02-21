import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:window_manager/window_manager.dart';

import 'injection.dart';
import 'presentation/app.dart';
import 'presentation/state/app_state.dart';
import 'presentation/state/theme_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize acrylic (transparent window effect) and window manager
  await Window.initialize();
  await windowManager.ensureInitialized();

  // 2. Setup dependency injection
  await setupDependencies();

  // 3. Initialize app state (load notes, create daily note)
  final appState = getIt<AppState>();
  await appState.initialize();

  // 4. Restore persisted theme settings
  final themeState = getIt<ThemeState>();
  await themeState.loadFromDisk();

  // 5. Configure: transparent + frameless + centered
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
