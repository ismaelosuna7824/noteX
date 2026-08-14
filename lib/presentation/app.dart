import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../injection.dart';
import 'pages/app_shell.dart';
import 'pages/mobile_app_shell.dart';
import 'pages/splash_screen.dart';
import 'state/app_state.dart';
import 'state/task_state.dart';
import 'state/theme_state.dart';
import 'utils/app_shortcuts.dart';
import 'utils/platform_utils.dart';
import 'widgets/shortcuts_help_sheet.dart';
import 'widgets/task_board.dart' show showAddTaskDialog;
import 'widgets/top_bar.dart' show TopBarState;

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

  /// Reaches [TopBarState.requestSearchFocus] for the Cmd/Ctrl+K app-wide
  /// shortcut. Owned here (not by `AppShell`) because `AppShortcuts` must be
  /// mounted above `MaterialApp`'s `Navigator` — see the `builder:` wiring
  /// below and `AppShortcuts`'s own doc comment for why.
  final GlobalKey<TopBarState> _topBarKey = GlobalKey<TopBarState>();

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

  // ── App-wide keyboard shortcuts (Cmd/Ctrl+N/Shift+N/Shift+T/K/…) ────────
  //
  // Lives here, not on `AppShell`, because `AppShortcuts` (below, wired via
  // `MaterialApp.builder`) must wrap the whole routed `Navigator` — including
  // every dialog route — not just the initial route's page content. See
  // `AppShortcuts`'s doc comment for the bug this placement fixes.

  void _handleNewNote() {
    widget.appState.createNewNote();
  }

  void _handleNewTask(BuildContext context) {
    showAddTaskDialog(context, getIt<TaskState>(), widget.themeState);
  }

  void _handleSearch() {
    _topBarKey.currentState?.requestSearchFocus();
  }

  void _handleShowShortcutsHelp(BuildContext context) {
    showShortcutsHelpSheet(context, widget.themeState);
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
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('es'),
          ],
          // Mounted above the `Navigator` (this `builder` wraps `child`,
          // which IS the built Navigator) so every route — including every
          // dialog — sits inside `AppShortcuts`'s focus-chain ancestry.
          // Desktop-only: matches the pre-existing scope of the app-wide
          // shortcut set (`kIsDesktop ? AppShell : MobileAppShell` below).
          builder: (context, child) {
            if (!kIsDesktop) return child!;
            return AppShortcuts(
              appState: widget.appState,
              onNewNote: _handleNewNote,
              onNewTask: _handleNewTask,
              onSearch: _handleSearch,
              onShowHelp: _handleShowShortcutsHelp,
              child: child!,
            );
          },
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
                          topBarKey: _topBarKey,
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
