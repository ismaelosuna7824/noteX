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

/// Handler for intents whose callback needs to show a dialog (a
/// [BuildContext] with real [Navigator]/[Theme] ancestors). [AppShortcuts]
/// is mounted above [MaterialApp]'s `Navigator` (via `builder`), so its own
/// `build` context is not a valid dialog context — but [ContextAction]
/// receives the context of whatever is actually focused when the shortcut
/// fires, which always has the real ancestor chain. See
/// `lib/presentation/app.dart` for why this widget lives above the
/// Navigator in the first place.
class _ContextCallbackAction<T extends Intent> extends ContextAction<T> {
  _ContextCallbackAction(this.onInvoke);
  final void Function(BuildContext context) onInvoke;

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    if (context != null) onInvoke(context);
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
///
/// **Must be mounted above `MaterialApp`'s `Navigator`** (via
/// `MaterialApp.builder`, see `lib/presentation/app.dart`), NOT as a
/// descendant of a route's page content (the original, buggy placement
/// inside `AppShell.build()`). `Shortcuts` dispatches by walking UP the
/// ancestor chain from whichever node currently holds focus — it never
/// looks at sibling subtrees. Every dialog in this app (`showDialog`,
/// `showAnimatedDialog`) pushes a new route that becomes a SIBLING of the
/// first route in the same `Navigator`'s `Overlay`, not a descendant of the
/// first route's page. A `Shortcuts` layer mounted inside that first
/// route's page is therefore structurally unreachable from a dialog's focus
/// chain — every shortcut silently stops firing (and macOS plays its
/// "unhandled key equivalent" beep) the moment any dialog is open. Mounting
/// above the `Navigator` makes this widget an ancestor of every route,
/// dialogs included.
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.appState,
    required this.child,
    required this.onNewNote,
    required this.onNewTask,
    required this.onSearch,
    required this.onShowHelp,
  });

  final AppState appState;
  final Widget child;
  final VoidCallback onNewNote;

  /// Needs a real dialog-capable [BuildContext] — this widget's own `build`
  /// context sits above the `Navigator`, so the framework-supplied
  /// invocation context (see [_ContextCallbackAction]) is used instead.
  final void Function(BuildContext context) onNewTask;
  final VoidCallback onSearch;

  /// Needs a real dialog-capable [BuildContext] — see [onNewTask].
  final void Function(BuildContext context) onShowHelp;

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
          NewTaskIntent: _ContextCallbackAction<NewTaskIntent>(onNewTask),
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) {
              onSearch();
              return null;
            },
          ),
          ShowShortcutsHelpIntent:
              _ContextCallbackAction<ShowShortcutsHelpIntent>(onShowHelp),
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
