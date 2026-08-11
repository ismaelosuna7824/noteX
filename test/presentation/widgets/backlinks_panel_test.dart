import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/get_backlinks_use_case.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/presentation/widgets/backlinks_panel.dart';

void main() {
  Backlink backlink({
    String id = 'n1',
    String title = 'Source note',
    String displayText = 'Source note',
  }) {
    return Backlink(
      source: Note(
        id: id,
        title: title,
        content: '',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      displayText: displayText,
    );
  }

  Future<List<String>> mountPanel(
    WidgetTester tester,
    List<Backlink> backlinks,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        // The ink splash is incidental to everything tested here, and loading
        // its shader throws under a Flutter SDK whose shaders were built for
        // Vulkan only (see the same failure in note_markdown_editor_test).
        // Dropping it keeps these cases about the panel, not about graphics.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: BacklinksPanel(
            backlinks: backlinks,
            onOpen: opened.add,
            accentColor: Colors.blue,
            textColor: Colors.black,
            mutedColor: Colors.grey,
            borderColor: Colors.black12,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('a note with no backlinks renders no chrome at all', (
    tester,
  ) async {
    await mountPanel(tester, const []);

    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining('linked mention'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('one backlink reads in the singular', (tester) async {
    await mountPanel(tester, [backlink()]);

    expect(find.text('1 linked mention'), findsOneWidget);
    expect(find.text('Source note'), findsOneWidget);
  });

  testWidgets('several backlinks read in the plural', (tester) async {
    await mountPanel(tester, [
      backlink(id: 'a', title: 'First'),
      backlink(id: 'b', title: 'Second'),
      backlink(id: 'c', title: 'Third'),
    ]);

    expect(find.text('3 linked mentions'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(3));
  });

  testWidgets('link text is surfaced when it differs from the title', (
    tester,
  ) async {
    await mountPanel(tester, [
      backlink(title: 'Hexagonal Architecture', displayText: 'the arch doc'),
    ]);

    expect(find.text('linked as "the arch doc"'), findsOneWidget);
  });

  testWidgets('link text is hidden when it just repeats the title', (
    tester,
  ) async {
    await mountPanel(tester, [backlink(title: 'Same', displayText: 'Same')]);

    expect(find.textContaining('linked as'), findsNothing);
  });

  testWidgets('an untitled source note still shows a label', (tester) async {
    await mountPanel(tester, [backlink(title: '   ', displayText: '')]);

    expect(find.text('Untitled'), findsOneWidget);
  });

  testWidgets('tapping a backlink asks the host to open that note', (
    tester,
  ) async {
    final opened = await mountPanel(tester, [backlink(id: 'target-id')]);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(opened, ['target-id']);
  });
}
