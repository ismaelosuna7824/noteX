import 'package:flutter/material.dart';

import '../state/theme_state.dart';
import '../utils/app_shortcuts.dart';
import 'animated_dialog.dart';

class _ShortcutEntry {
  const _ShortcutEntry(this.keys, this.description);
  final String keys;
  final String description;
}

/// Shows the "Keyboard Shortcuts" help sheet listing every app-wide
/// shortcut with its action.
///
/// Rendered on `ThemeState.editorBgColor`, like the app's other dialogs
/// (`showAddTaskDialog`, the task detail dialog, note modals) — not
/// [AlertDialog]'s `ColorScheme.fromSeed`-derived default, which reads
/// off-theme against this app's accent color.
///
/// Reachable only via Cmd/Ctrl+/ for now — there is no on-screen button
/// that opens it, so a keyboard-less user currently cannot reach it.
Future<void> showShortcutsHelpSheet(
  BuildContext context,
  ThemeState themeState,
) {
  final mod = primaryModifierLabel;
  final entries = [
    _ShortcutEntry(
      '$mod+1 … $mod+$kNumberedSectionShortcutCount',
      'Jump to a sidebar section',
    ),
    _ShortcutEntry('$mod+N', 'New note'),
    _ShortcutEntry('$mod+Shift+N', 'New task'),
    _ShortcutEntry('$mod+Shift+T', 'Start / stop the timer'),
    _ShortcutEntry('$mod+K', 'Search'),
    _ShortcutEntry('$mod+/', 'Show this shortcuts list'),
  ];

  return showAnimatedDialog<void>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final accentColor = themeState.accentColor;
      final textColor = themeState.editorTextColor;
      final mutedTextColor = themeState.editorMutedTextColor;

      return AlertDialog(
        // Same theme fix as every other dialog in this app (task detail
        // dialog, New Task dialog, note modals) — the app's own
        // dark-neutral surface, not AlertDialog's default.
        backgroundColor: Color.alphaBlend(
          themeState.editorBgColor.withValues(alpha: 0.96),
          isDark ? Colors.black : Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Keyboard Shortcuts',
          style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entry.keys,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: accentColor.computeLuminance() > 0.5
                                ? Colors.black
                                : accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          entry.description,
                          style: TextStyle(fontSize: 14, color: mutedTextColor),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: accentColor),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
