import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/markdown/markdown_list.dart';
import 'package:notex/presentation/widgets/note_markdown_editor.dart';

/// Ticking a box in the preview and seeing it tick.
///
/// The preview used to be a read-only surface, so the editor only rebuilt it
/// on a keystroke in split mode — in preview mode the field is not on screen,
/// so nothing could change the document and a rebuild would have been waste.
/// Making checkboxes pressable broke that premise: the preview can now change
/// the document itself. Without a rebuild the box stays as it was until some
/// unrelated thing — the autosave indicator, a resize — happens to rebuild the
/// editor, which reads as a checkbox that ignores the first click.
void main() {
  Future<String?> pumpEditor(
    WidgetTester tester, {
    required String content,
    required EditorViewMode mode,
    bool readOnly = false,
  }) async {
    String? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NoteMarkdownEditor(
              initialContent: content,
              initialViewMode: mode,
              readOnly: readOnly,
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return changed;
  }

  bool isChecked(WidgetTester tester) =>
      find.byIcon(Icons.check_rounded).evaluate().isNotEmpty;

  for (final mode in [EditorViewMode.preview, EditorViewMode.split]) {
    testWidgets('in ${mode.name} mode, a tapped box ticks on the same frame', (
      tester,
    ) async {
      await pumpEditor(tester, content: '- [ ] one', mode: mode);
      expect(isChecked(tester), isFalse);

      await tester.tap(find.byKey(markdownTaskKey(0)));
      // Only a frame. Nothing else rebuilds the editor here, which is exactly
      // the point: the preview has to redraw off its own change.
      await tester.pump();

      expect(
        isChecked(tester),
        isTrue,
        reason: 'the box did not redraw after its own tap',
      );
    });

    testWidgets('in ${mode.name} mode, tapping again unticks it', (
      tester,
    ) async {
      await pumpEditor(tester, content: '- [x] one', mode: mode);
      expect(isChecked(tester), isTrue);

      await tester.tap(find.byKey(markdownTaskKey(0)));
      await tester.pump();

      expect(isChecked(tester), isFalse);
    });
  }

  testWidgets('the tap reaches the host as a document change', (tester) async {
    String? changed;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NoteMarkdownEditor(
              initialContent: '- [ ] one\n- [ ] two',
              initialViewMode: EditorViewMode.preview,
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(markdownTaskKey(1)));
    await tester.pump();

    expect(changed, '- [ ] one\n- [x] two');
  });

  testWidgets('a read-only preview draws the boxes but does not change them', (
    tester,
  ) async {
    final changed = await pumpEditor(
      tester,
      content: '- [ ] one',
      mode: EditorViewMode.preview,
      readOnly: true,
    );

    expect(find.byKey(markdownTaskKey(0)), findsOneWidget);
    await tester.tap(find.byKey(markdownTaskKey(0)));
    await tester.pump();

    expect(isChecked(tester), isFalse);
    expect(changed, isNull);
  });
}
