import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'pages/app_shell.dart';
import 'pages/mobile_app_shell.dart';
import 'pages/splash_screen.dart';
import 'state/app_state.dart';
import 'state/theme_state.dart';
import 'utils/platform_utils.dart';

/// Root MaterialApp with dynamic theming.
class NoteXApp extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const NoteXApp({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<NoteXApp> createState() => _NoteXAppState();
}

class _NoteXAppState extends State<NoteXApp> {
  bool _showSplash = true;
  bool _fadingOut = false;
  bool _splashDone = false;

  void _onSplashComplete() {
    setState(() => _fadingOut = true);
  }

  void _onFadeOutDone() {
    if (_fadingOut && mounted) {
      setState(() {
        _showSplash = false;
        _splashDone = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.appState, widget.themeState]),
      builder: (context, _) {
        return MaterialApp(
          title: 'NoteX',
          debugShowCheckedModeBanner: false,
          color: Colors.transparent,
          theme: widget.themeState.buildTheme(),
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
          home: _showSplash
              ? AnimatedOpacity(
                  opacity: _fadingOut ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                  onEnd: _onFadeOutDone,
                  child: SplashScreen(onComplete: _onSplashComplete),
                )
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - t)),
                      child: child,
                    ),
                  ),
                  child: kIsDesktop
                      ? AppShell(
                          appState: widget.appState,
                          themeState: widget.themeState,
                        )
                      : MobileAppShell(
                          appState: widget.appState,
                          themeState: widget.themeState,
                        ),
                ),
        );
      },
    );
  }
}
