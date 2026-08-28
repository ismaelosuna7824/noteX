import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/note_markdown_editor.dart';

/// The toolbar writes into the document, so the caret has to end up back in the
/// document. Otherwise the focus sits on the button that was just pressed and
/// Cmd/Ctrl+Z — dispatched to whatever is focused — does nothing until the
/// reader clicks into the text, which is the one moment they are most likely to
/// want to take the insert back.
void main() {
  Future<void> pump(WidgetTester tester, EditorViewMode mode) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: NoteMarkdownEditor(
              initialContent: 'hello',
              initialViewMode: mode,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  for (final button in ['Bold', 'Checklist', 'Bullet list', 'Heading 1']) {
    testWidgets('$button leaves focus in the field', (tester) async {
      await pump(tester, EditorViewMode.edit);

      await tester.tap(find.byTooltip(button));
      await tester.pumpAndSettle();

      expect(fieldHasFocus(tester), isTrue, reason: '$button kept the focus');
    });
  }

  testWidgets('in split mode the field keeps focus too', (tester) async {
    await pump(tester, EditorViewMode.split);
    await tester.tap(find.byTooltip('Bold'));
    await tester.pumpAndSettle();
    expect(fieldHasFocus(tester), isTrue);
  });
}
