import 'package:flutter/material.dart';

import '../state/theme_state.dart';
import '../utils/app_shortcuts.dart';
import 'animated_dialog.dart';

/// One row of the app-wide keyboard shortcut list: the key combination and
/// what it does.
class ShortcutEntry {
  const ShortcutEntry(this.keys, this.description);
  final String keys;
  final String description;
}

/// The canonical list of app-wide keyboard shortcuts, formatted with the
/// current platform's primary modifier ([primaryModifierLabel]: ⌘ on macOS,
/// "Ctrl" elsewhere).
///
/// **Single source of truth**: both surfaces that show the shortcut list —
/// this file's [showShortcutsHelpSheet] (Cmd/Ctrl+/) and the Settings page's
/// "Keyboard Shortcuts" section (`KeyboardShortcutsList` below, embedded via
/// `_buildKeyboardShortcutsSection` in `settings_page.dart`) — read this
/// function instead of keeping their own copy. Add a shortcut here once and
/// both surfaces pick it up automatically; a test in
/// `keyboard_shortcuts_list_test.dart` asserts the settings section renders
/// an entry for every item this function returns, so a shortcut added only
/// to one surface fails the suite.
List<ShortcutEntry> buildShortcutEntries() {
  final mod = primaryModifierLabel;
  return [
    ShortcutEntry(
      '$mod+1 … $mod+$kNumberedSectionShortcutCount',
      'Jump to a sidebar section',
    ),
    ShortcutEntry('$mod+N', 'New note'),
    ShortcutEntry('$mod+Shift+N', 'New task'),
    ShortcutEntry('$mod+K', 'Search'),
    ShortcutEntry('$mod+/', 'Show this shortcuts list'),
  ];
}

/// Renders a single [ShortcutEntry] as a key chip + description row —
/// shared by the help sheet and the Settings page section so their visual
/// treatment of a row stays identical, not just the underlying data.
Widget buildShortcutRow(
  ShortcutEntry entry, {
  required Color accentColor,
  required Color descriptionColor,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            style: TextStyle(fontSize: 14, color: descriptionColor),
          ),
        ),
      ],
    ),
  );
}

/// The row list rendered inside the Settings page's "Keyboard Shortcuts"
/// section (see `_buildKeyboardShortcutsSection` in `settings_page.dart`).
///
/// Purely informational — no interactive elements, so it needs no
/// [Material] ancestor (unlike the `SwitchListTile` fix at
/// `settings_page.dart:667-702`, which IS interactive and does need one).
/// Renders one row per entry in [buildShortcutEntries], the same shared
/// definition the ⌘/ help sheet reads.
class KeyboardShortcutsList extends StatelessWidget {
  const KeyboardShortcutsList({
    super.key,
    required this.accentColor,
    required this.descriptionColor,
  });

  final Color accentColor;
  final Color descriptionColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in buildShortcutEntries())
          Semantics(
            label: '${entry.keys}: ${entry.description}',
            child: buildShortcutRow(
              entry,
              accentColor: accentColor,
              descriptionColor: descriptionColor,
            ),
          ),
      ],
    );
  }
}

/// Shows the "Keyboard Shortcuts" help sheet listing every app-wide
/// shortcut with its action.
///
/// Rendered on `ThemeState.editorBgColor`, like the app's other dialogs
/// (`showAddTaskDialog`, the task detail dialog, note modals) — not
/// [AlertDialog]'s `ColorScheme.fromSeed`-derived default, which reads
/// off-theme against this app's accent color.
///
/// Reachable via Cmd/Ctrl+/, and now also discoverable on-screen through
/// the Settings page's "Keyboard Shortcuts" section (`KeyboardShortcutsList`
/// above) — a keyboard-less user, or one who hasn't learned the shortcut
/// yet, can find the same list there.
Future<void> showShortcutsHelpSheet(
  BuildContext context,
  ThemeState themeState,
) {
  final entries = buildShortcutEntries();

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
                buildShortcutRow(
                  entry,
                  accentColor: accentColor,
                  descriptionColor: mutedTextColor,
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
