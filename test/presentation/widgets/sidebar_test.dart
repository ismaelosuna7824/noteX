import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/utils/app_shortcuts.dart';
import 'package:notex/presentation/widgets/sidebar.dart';

/// Covers hiding the Markdown section from the desktop sidebar: the entry
/// must not render, and — since [Sidebar] maps taps straight through to
/// [Sidebar.onItemSelected] with the page index baked into each tuple —
/// every surviving item must still report the exact page index it always
/// has. This is the guard against a positional index shift: if a future
/// edit ever rewrote `_navItems` to derive indices from list position
/// instead of carrying them explicitly, this test would catch every
/// item after the removed slot pointing one page too early.
///
/// Also covers each section's hover tooltip showing its numeric jump
/// shortcut (`Sidebar.sectionTooltip`), matching the pattern the editor's
/// preview/split buttons already use.
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
    // Pinned so the tooltip text this test taps by is deterministic
    // regardless of the host running the suite — see the "modifier label
    // matches the platform" tests below for the platform-dependent half.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final selected = <int>[];
      await tester.pumpWidget(
        buildSidebar(onItemSelected: selected.add),
      );

      // (label, expected page index, 1-based position in the sidebar) — the
      // exact pairs Sidebar wires today, minus Markdown. If removing
      // Markdown ever shifted a later item's index, one of these taps would
      // report the wrong number. The tooltip itself is derived through
      // Sidebar.sectionTooltip (the same function production code uses),
      // never a hand-typed "Label (⌘+N)" string, so it can't drift from the
      // real tooltip text.
      const expected = [
        ('Home', 0, 1),
        ('Notes', 1, 2),
        ('Editor', 2, 3),
        ('Calendar', 3, 4),
        ('Timer', 4, 5),
        ('Graph', 9, 6),
        ('Tasks', 7, 7),
        ('Trash', 8, 8),
        ('Settings', 6, 9),
      ];

      for (final (label, pageIndex, position) in expected) {
        selected.clear();
        await tester.tap(
          find.byTooltip(Sidebar.sectionTooltip(label, position)),
        );
        await tester.pump();
        expect(
          selected,
          [pageIndex],
          reason: '"$label" should still navigate to page $pageIndex',
        );
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      "a sidebar section's tooltip contains its shortcut, derived from the "
      'shared definition rather than a literal', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(buildSidebar(onItemSelected: (_) {}));

      // Built from Sidebar.sectionTooltip + primaryModifierLabel, not a
      // literal '⌘1' typed into this test — if the app-wide shortcut or its
      // formatting ever changed, this assertion changes with it instead of
      // silently going stale.
      expect(
        find.byTooltip(Sidebar.sectionTooltip('Home', 1)),
        findsOneWidget,
      );
      expect(
        Sidebar.sectionTooltip('Home', 1),
        contains(primaryModifierLabel),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('Sidebar.sectionTooltip', () {
    test('includes the numeric shortcut for a position within range', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        expect(Sidebar.sectionTooltip('Home', 1), 'Home (⌘+1)');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('omits the shortcut hint for a position beyond the numbered range',
        () {
      // A section past kNumberedSectionShortcutCount has no shortcut bound
      // to it — the tooltip must show only the label, never a wrong hint.
      expect(
        Sidebar.sectionTooltip('Extra', kNumberedSectionShortcutCount + 1),
        'Extra',
      );
    });

    test('uses the platform-appropriate modifier', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        expect(Sidebar.sectionTooltip('Notes', 2), contains('⌘'));
        expect(Sidebar.sectionTooltip('Notes', 2), isNot(contains('Ctrl')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect(Sidebar.sectionTooltip('Notes', 2), 'Notes (Ctrl+2)');
        expect(Sidebar.sectionTooltip('Notes', 2), isNot(contains('⌘')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  test(
      'visiblePageIndices/visibleSectionLabels expose the exact list the '
      'sidebar renders from, in the same order', () {
    // The app-wide numeric shortcuts (Cmd/Ctrl+1..8, see `AppShortcuts`)
    // derive their mapping from these getters instead of a hand-copied
    // list — this pins them to the private `_navItems` source so hiding or
    // reordering a sidebar section can never silently drift out of sync.
    expect(Sidebar.visiblePageIndices, [0, 1, 2, 3, 4, 9, 7, 8, 6]);
    expect(
      Sidebar.visibleSectionLabels,
      [
        'Home',
        'Notes',
        'Editor',
        'Calendar',
        'Timer',
        'Graph',
        'Tasks',
        'Trash',
        'Settings',
      ],
    );
    expect(
      Sidebar.visiblePageIndices.length,
      Sidebar.visibleSectionLabels.length,
    );
  });
}
