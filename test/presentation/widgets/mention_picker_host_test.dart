import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/presentation/widgets/mention_picker_host.dart';
import 'package:notex/presentation/widgets/note_markdown_editor.dart';

/// Covers the seam the earlier tests skipped: the picker reaching the editor
/// through [MentionPickerHost.mentionEditorKey].
///
/// The previous editor test called `commitMention` directly on the state, so it
/// never exercised the key lookup — and missed that a `GlobalObjectKey` built
/// from an interpolated string can never match, because its `==` uses
/// `identical` on the value. This drives the whole path from tap to text.
class _Host extends StatefulWidget {
  final List<Note> notes;
  final String currentNoteId;
  final ValueChanged<String> onChanged;

  const _Host({
    required this.notes,
    required this.currentNoteId,
    required this.onChanged,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with MentionPickerHost {
  final GlobalKey<NoteMarkdownEditorState> _editorKey = GlobalKey();

  @override
  GlobalKey<NoteMarkdownEditorState>? get mentionEditorKey => _editorKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NoteMarkdownEditor(
          key: _editorKey,
          initialContent: '',
          onChanged: widget.onChanged,
          onMentionQuery: onMentionQuery,
        ),
        buildMentionOverlay(
          notes: widget.notes,
          currentNoteId: widget.currentNoteId,
          accentColor: Colors.blue,
          bgColor: Colors.white,
          borderColor: Colors.black12,
          textColor: Colors.black,
          mutedColor: Colors.grey,
        ),
      ],
    );
  }
}

void main() {
  Note note(String id, String title) => Note(
    id: id,
    title: title,
    content: '',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  late List<String> changes;

  Future<void> mountHost(WidgetTester tester, List<Note> notes) async {
    changes = [];
    await tester.pumpWidget(
      MaterialApp(
        // The splash shader is unavailable under this SDK; it is irrelevant
        // here and would otherwise throw on tap.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: _Host(
              notes: notes,
              currentNoteId: 'current',
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing @ opens the picker with candidate notes', (tester) async {
    await mountHost(tester, [note('a', 'Supabase'), note('b', 'Figma')]);

    await tester.enterText(find.byType(TextField), 'see @Sup');
    await tester.pumpAndSettle();

    expect(find.text('Supabase'), findsOneWidget);
    expect(find.text('Figma'), findsNothing);
  });

  testWidgets('tapping a note inserts the link — the key lookup must resolve', (
    tester,
  ) async {
    await mountHost(tester, [note('abc-123', 'Supabase')]);

    await tester.enterText(find.byType(TextField), 'see @Sup');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Supabase'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'see [Supabase](notex://abc-123)');
    expect(changes.last, 'see [Supabase](notex://abc-123)');
  });

  testWidgets('the picker closes once a note is chosen', (tester) async {
    await mountHost(tester, [note('abc-123', 'Supabase')]);

    await tester.enterText(find.byType(TextField), '@Sup');
    await tester.pumpAndSettle();
    expect(find.text('Supabase'), findsOneWidget);

    await tester.tap(find.text('Supabase'));
    await tester.pumpAndSettle();

    expect(find.text('Supabase'), findsNothing);
  });

  testWidgets('the note being edited is never offered as a candidate', (
    tester,
  ) async {
    await mountHost(tester, [note('current', 'This note'), note('a', 'Other')]);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pumpAndSettle();

    expect(find.text('This note'), findsNothing);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('deleting the @ closes the picker in one keystroke', (
    tester,
  ) async {
    await mountHost(tester, [note('a', 'Supabase')]);

    await tester.enterText(find.byType(TextField), 'see @');
    await tester.pumpAndSettle();
    expect(find.text('Supabase'), findsOneWidget);

    // Backspacing away the '@' must dismiss it, not leave it stuck open.
    await tester.enterText(find.byType(TextField), 'see ');
    await tester.pumpAndSettle();

    expect(find.text('Supabase'), findsNothing);
  });
}
