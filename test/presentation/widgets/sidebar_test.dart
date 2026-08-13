import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/sidebar.dart';

/// Covers hiding the Markdown section from the desktop sidebar: the entry
/// must not render, and — since [Sidebar] maps taps straight through to
/// [Sidebar.onItemSelected] with the page index baked into each tuple —
/// every surviving item must still report the exact page index it always
/// has. This is the guard against a positional index shift: if a future
/// edit ever rewrote `_navItems` to derive indices from list position
/// instead of carrying them explicitly, this test would catch every
/// item after the removed slot pointing one page too early.
void main() {
  Widget buildSidebar({required ValueChanged<int> onItemSelected}) {
    return MaterialApp(
      home: Scaffold(
        body: Sidebar(
          selectedIndex: 0,
          onItemSelected: onItemSelected,
          accentColor: Colors.blue,
          editorBgColor: Colors.white,
          heroTextColor: Colors.black,
          heroShadows: const [],
          baseIconColor: Colors.black54,
        ),
      ),
    );
  }

  testWidgets('Markdown entry is not rendered in the sidebar',
      (tester) async {
    await tester.pumpWidget(buildSidebar(onItemSelected: (_) {}));

    expect(find.byTooltip('Markdown'), findsNothing);
    expect(find.byIcon(Icons.article_rounded), findsNothing);
  });

  testWidgets('every remaining sidebar item still opens the page it names',
      (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      buildSidebar(onItemSelected: selected.add),
    );

    // (tooltip label, expected page index) — the exact pairs Sidebar wires
    // today, minus Markdown. If removing Markdown ever shifted a later
    // item's index, one of these taps would report the wrong number.
    const expected = [
      ('Home', 0),
      ('Notes', 1),
      ('Editor', 2),
      ('Calendar', 3),
      ('Timer', 4),
      ('Graph', 9),
      ('Tasks', 7),
      ('Trash', 8),
      ('Settings', 6),
    ];

    for (final (label, pageIndex) in expected) {
      selected.clear();
      await tester.tap(find.byTooltip(label));
      await tester.pump();
      expect(
        selected,
        [pageIndex],
        reason: '"$label" should still navigate to page $pageIndex',
      );
    }
  });
}
