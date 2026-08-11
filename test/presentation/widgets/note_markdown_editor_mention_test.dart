import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/services/mention_trigger.dart';
import 'package:notex/presentation/widgets/note_markdown_editor.dart';

/// Covers the editor's @mention surface: reporting the composing token and
/// committing a chosen note back into the document. The grammar itself is
/// tested in test/domain/services/mention_trigger_test.dart — this is about
/// the wiring between the TextField and the host.
void main() {
  late List<MentionQuery?> reported;
  late List<String> changes;
  late GlobalKey<NoteMarkdownEditorState> editorKey;

  Future<void> mountEditor(WidgetTester tester, {String content = ''}) async {
    reported = [];
    changes = [];
    editorKey = GlobalKey<NoteMarkdownEditorState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NoteMarkdownEditor(
              key: editorKey,
              initialContent: content,
              onChanged: changes.add,
              onMentionQuery: reported.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing an @ opens a mention with an empty query', (tester) async {
    await mountEditor(tester);
    await tester.enterText(find.byType(TextField), 'see @');
    await tester.pump();

    expect(reported.last, isNotNull);
    expect(reported.last!.query, '');
  });

  testWidgets('typing after the @ reports the growing query', (tester) async {
    await mountEditor(tester);
    await tester.enterText(find.byType(TextField), 'see @hex');
    await tester.pump();

    expect(reported.last!.query, 'hex');
  });

  testWidgets('an email address never opens a mention', (tester) async {
    await mountEditor(tester);
    await tester.enterText(find.byType(TextField), 'mail user@example');
    await tester.pump();

    expect(reported.last, isNull);
  });

  testWidgets('a space after the query closes the mention', (tester) async {
    await mountEditor(tester);
    await tester.enterText(find.byType(TextField), 'see @hex');
    await tester.pump();
    expect(reported.last, isNotNull);

    await tester.enterText(find.byType(TextField), 'see @hex ');
    await tester.pump();
    expect(reported.last, isNull);
  });

  testWidgets('loading a note never opens a picker', (tester) async {
    // Programmatic controller seeding must not look like typing.
    await mountEditor(tester, content: 'existing @content');
    expect(reported, isEmpty);
  });

  testWidgets('committing replaces the token with a Markdown link',
      (tester) async {
    await mountEditor(tester);
    await tester.enterText(find.byType(TextField), 'see @hex');
    await tester.pump();

    editorKey.currentState!.commitMention(
      trigger: reported.last!,
      noteId: 'abc-123',
      displayText: 'Hexagonal Architecture',
    );
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller!.text,
      'see [Hexagonal Architecture](notex://abc-123)',
    );
  });

  testWidgets('committing fires onChanged so the host can save',
      (tester) async {
    await mountEditor(tester);
    await tester.enterText(find.byType(TextField), '@h');
    await tester.pump();

    editorKey.currentState!.commitMention(
      trigger: reported.last!,
      noteId: 'x',
      displayText: 'Note',
    );
    await tester.pump();

    expect(changes.last, '[Note](notex://x)');
  });

  testWidgets('committing closes the picker and leaves the caret after the link',
      (tester) async {
    await mountEditor(tester);
    await tester.enterText(find.byType(TextField), '@h');
    await tester.pump();

    editorKey.currentState!.commitMention(
      trigger: reported.last!,
      noteId: 'x',
      displayText: 'Note',
    );
    await tester.pump();

    expect(reported.last, isNull);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller!.selection.baseOffset,
      field.controller!.text.length,
    );
  });
}
