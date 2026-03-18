import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'pages/app_shell.dart';
import 'pages/mobile_app_shell.dart';
import 'state/app_state.dart';
import 'state/theme_state.dart';
import 'utils/platform_utils.dart';

/// Root MaterialApp with dynamic theming.
class NoteXApp extends StatelessWidget {
  final AppState appState;
  final ThemeState themeState;

  const NoteXApp({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([appState, themeState]),
      builder: (context, _) {
        return MaterialApp(
          title: 'NoteX',
          debugShowCheckedModeBanner: false,
          color: Colors.transparent,
          theme: themeState.buildTheme(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('es'),
          ],
          home: kIsDesktop
              ? AppShell(
                  appState: appState,
                  themeState: themeState,
                )
              : MobileAppShell(
                  appState: appState,
                  themeState: themeState,
                ),
        );
      },
    );
  }
}
