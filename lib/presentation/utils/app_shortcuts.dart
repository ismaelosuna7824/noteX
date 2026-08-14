import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../widgets/sidebar.dart';

/// Whether the running platform's primary shortcut modifier is Cmd (macOS)
/// rather than Ctrl (Windows/Linux/other) — NoteX ships all three desktop
/// platforms, so shortcuts must never hardcode one modifier.
bool get isPrimaryModifierMeta => defaultTargetPlatform == TargetPlatform.macOS;

/// The modifier glyph to show in shortcut hints for the running platform:
/// ⌘ on macOS, "Ctrl" elsewhere.
String get primaryModifierLabel => isPrimaryModifierMeta ? '⌘' : 'Ctrl';

/// Builds a [SingleActivator] for [key] using the platform's primary
/// modifier (Cmd on macOS, Ctrl elsewhere), optionally combined with Shift.
SingleActivator primaryActivator(LogicalKeyboardKey key, {bool shift = false}) {
  return SingleActivator(
    key,
    meta: isPrimaryModifierMeta,
    control: !isPrimaryModifierMeta,
    shift: shift,
  );
}

/// How many leading visible sidebar sections get a numeric jump shortcut
/// (Cmd/Ctrl+1..8). The settled shortcut set only defines 1-8; if the
/// sidebar ever shows more sections than this, the extra ones simply have
/// no numeric shortcut yet — see [Sidebar.visiblePageIndices] for the full
/// list actually rendered.
const int kNumberedSectionShortcutCount = 8;

const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
];

// ─── Intents ────────────────────────────────────────────────────────────────

/// Jump to the sidebar section shown at [position] (1-based), per
/// [Sidebar.visiblePageIndices] — the same order the sidebar itself renders,
/// so a hidden or reordered section keeps every numeric shortcut correct
/// instead of pointing at a raw, possibly-hidden page index.
class NavigateToVisibleSectionIntent extends Intent {
  const NavigateToVisibleSectionIntent(this.position);
  final int position;
}

class NewNoteIntent extends Intent {
  const NewNoteIntent();
}

class NewTaskIntent extends Intent {
  const NewTaskIntent();
}

class ToggleTimerIntent extends Intent {
  const ToggleTimerIntent();
}

class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

class ShowShortcutsHelpIntent extends Intent {
  const ShowShortcutsHelpIntent();
}

class ToggleZenModeIntent extends Intent {
  const ToggleZenModeIntent();
}

class ExitZenModeIntent extends Intent {
  const ExitZenModeIntent();
}

/// Exits zen mode only when it is actually active — mirrors the app's old
/// `Focus.onKeyEvent` guard (`if (... && appState.isZenMode)`) so Escape
/// still falls through to any other handler (e.g. a dialog's own
/// dismiss-on-Escape) when zen mode is off, instead of being swallowed here.
class _ExitZenModeAction extends Action<ExitZenModeIntent> {
  _ExitZenModeAction(this.appState);
  final AppState appState;

  @override
  bool get isActionEnabled => appState.isZenMode;

  @override
  Object? invoke(ExitZenModeIntent intent) {
    appState.exitZenMode();
    return null;
  }
}

/// App-wide keyboard shortcuts: sidebar navigation, note/task creation, the
/// timer toggle, search, the shortcuts help sheet, and zen mode (F11 /
/// Escape) — the single [Shortcuts]/[Actions] layer for the whole desktop
/// app shell.
///
/// This absorbs the app-wide keyboard mechanism that used to live directly
/// in `AppShell` (a `Focus.onKeyEvent` handling F11/Escape): every app-wide
/// binding now goes through Flutter's own focus-scoped Shortcuts/Actions
/// system instead of a hand-rolled key listener. The editor's own
/// Cmd/Ctrl+E toggles are a separate, narrower Shortcuts/Actions binding
/// scoped to `NoteMarkdownEditor` itself (see that file) — Flutter's own
/// focus-subtree scoping is what lets both layers coexist without either
/// hand-rolling an "which instance is active" guard.
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.appState,
    required this.child,
    required this.onNewNote,
    required this.onNewTask,
    required this.onToggleTimer,
    required this.onSearch,
    required this.onShowHelp,
  });

  final AppState appState;
  final Widget child;
  final VoidCallback onNewNote;
  final VoidCallback onNewTask;
  final VoidCallback onToggleTimer;
  final VoidCallback onSearch;
  final VoidCallback onShowHelp;

  @override
  Widget build(BuildContext context) {
    final indices = Sidebar.visiblePageIndices;
    final sectionCount = indices.length < kNumberedSectionShortcutCount
        ? indices.length
        : kNumberedSectionShortcutCount;

    return Shortcuts(
      shortcuts: {
        for (var i = 1; i <= sectionCount; i++)
          primaryActivator(_digitKeys[i - 1]):
              NavigateToVisibleSectionIntent(i),
        primaryActivator(LogicalKeyboardKey.keyN): const NewNoteIntent(),
        primaryActivator(LogicalKeyboardKey.keyN, shift: true):
            const NewTaskIntent(),
        primaryActivator(LogicalKeyboardKey.keyT, shift: true):
            const ToggleTimerIntent(),
        primaryActivator(LogicalKeyboardKey.keyK): const FocusSearchIntent(),
        primaryActivator(LogicalKeyboardKey.slash):
            const ShowShortcutsHelpIntent(),
        const SingleActivator(LogicalKeyboardKey.f11):
            const ToggleZenModeIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const ExitZenModeIntent(),
      },
      child: Actions(
        actions: {
          NavigateToVisibleSectionIntent:
              CallbackAction<NavigateToVisibleSectionIntent>(
            onInvoke: (intent) {
              final targets = Sidebar.visiblePageIndices;
              if (intent.position < 1 || intent.position > targets.length) {
                return null;
              }
              appState.navigateToPage(targets[intent.position - 1]);
              return null;
            },
          ),
          NewNoteIntent: CallbackAction<NewNoteIntent>(
            onInvoke: (_) {
              onNewNote();
              return null;
            },
          ),
          NewTaskIntent: CallbackAction<NewTaskIntent>(
            onInvoke: (_) {
              onNewTask();
              return null;
            },
          ),
          ToggleTimerIntent: CallbackAction<ToggleTimerIntent>(
            onInvoke: (_) {
              onToggleTimer();
              return null;
            },
          ),
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) {
              onSearch();
              return null;
            },
          ),
          ShowShortcutsHelpIntent: CallbackAction<ShowShortcutsHelpIntent>(
            onInvoke: (_) {
              onShowHelp();
              return null;
            },
          ),
          ToggleZenModeIntent: CallbackAction<ToggleZenModeIntent>(
            onInvoke: (_) {
              appState.toggleZenMode();
              return null;
            },
          ),
          ExitZenModeIntent: _ExitZenModeAction(appState),
        },
        child: child,
      ),
    );
  }
}
