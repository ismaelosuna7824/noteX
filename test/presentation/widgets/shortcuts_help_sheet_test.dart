import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/state/theme_state.dart';
import 'package:notex/presentation/widgets/shortcuts_help_sheet.dart';

/// Covers the Cmd/Ctrl+/ help sheet: it lists every app-wide shortcut and
/// shows the modifier glyph that matches the running platform.
void main() {
  Future<void> pumpAndOpen(WidgetTester tester, ThemeState themeState) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    unawaited(showShortcutsHelpSheet(capturedContext, themeState));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every app-wide shortcut with its action', (tester) async {
    await pumpAndOpen(tester, ThemeState());

    expect(find.text('Keyboard Shortcuts'), findsOneWidget);

    // Driven by the shared definition rather than a hardcoded copy: adding
    // or removing a shortcut updates this assertion automatically, so the
    // sheet and the list can never drift apart. A hardcoded list here had
    // to be edited by hand every time the set changed, which is exactly the
    // duplication `buildShortcutEntries()` exists to prevent.
    for (final entry in buildShortcutEntries()) {
      expect(
        find.text(entry.description),
        findsOneWidget,
        reason: 'the help sheet must list "${entry.description}"',
      );
    }
  });

  testWidgets('shows the Cmd glyph on macOS', (tester) async {
    // Must be restored inside the test body (try/finally) — the framework
    // asserts no foundation debug variable is left changed, and that check
    // runs before any addTearDown callback (same pattern as
    // task_board_test.dart).
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpAndOpen(tester, ThemeState());

      expect(find.textContaining('⌘'), findsWidgets);
      expect(find.textContaining('Ctrl'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows "Ctrl" on Windows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpAndOpen(tester, ThemeState());

      expect(find.textContaining('Ctrl'), findsWidgets);
      expect(find.textContaining('⌘'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Close button dismisses the sheet', (tester) async {
    await pumpAndOpen(tester, ThemeState());
    expect(find.text('Keyboard Shortcuts'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Keyboard Shortcuts'), findsNothing);
  });
}
