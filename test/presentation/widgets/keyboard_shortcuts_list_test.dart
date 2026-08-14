import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/shortcuts_help_sheet.dart';

/// Covers `KeyboardShortcutsList`, the widget embedded in the Settings
/// page's "Keyboard Shortcuts" section.
///
/// This is the anti-drift test the shortcuts-discoverability brief asks
/// for: it never hardcodes the shortcut list, it always iterates
/// [buildShortcutEntries] — the same shared definition the ⌘/ help sheet
/// reads (see `shortcuts_help_sheet_test.dart`). If a shortcut is ever
/// added to [buildShortcutEntries] but the Settings section fails to
/// render it, this test starts failing automatically; if a shortcut is
/// added to only the help sheet's own copy instead of the shared
/// definition, it silently would NOT show up here, which is exactly the
/// drift this design prevents by construction (there is no second copy to
/// forget).
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KeyboardShortcutsList(
            accentColor: Colors.blue,
            descriptionColor: Colors.grey,
          ),
        ),
      ),
    );
  }

  testWidgets('renders an entry for every shortcut in the shared definition', (
    tester,
  ) async {
    await pump(tester);

    final entries = buildShortcutEntries();
    expect(entries, isNotEmpty);

    for (final entry in entries) {
      expect(
        find.text(entry.keys),
        findsOneWidget,
        reason: 'missing key chip for "${entry.description}"',
      );
      expect(
        find.text(entry.description),
        findsOneWidget,
        reason: 'missing description for "${entry.keys}"',
      );
    }
  });

  testWidgets('shows the Cmd glyph on macOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pump(tester);

      expect(find.textContaining('⌘'), findsWidgets);
      expect(find.textContaining('Ctrl'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows "Ctrl" on Windows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pump(tester);

      expect(find.textContaining('Ctrl'), findsWidgets);
      expect(find.textContaining('⌘'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
