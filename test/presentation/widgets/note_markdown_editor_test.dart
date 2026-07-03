import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/note_markdown_editor.dart';

void main() {
  /// Pumps [child] inside a minimal MaterialApp shell and settles it.
  Future<void> mountEditor(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Extra frames: any spurious post-frame document change would surface here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  // Sample content in every accepted input shape.
  const legacyDelta =
      '[{"insert":"Hello "},{"insert":"world","attributes":{"bold":true}},'
      '{"insert":"\\n"}]';
  // The converter renders the legacy Delta above to this Markdown.
  const legacyDeltaMarkdown = 'Hello **world**';
  const markdown = '# Title\n\nSome **bold** text and a bullet:\n\n- one\n- two';
  const emptyDelta = '[]';

  final inputs = <String, String>{
    'legacy Delta JSON': legacyDelta,
    'markdown': markdown,
    "empty '[]'": emptyDelta,
  };

  // The Markdown the TextField should show for each input after conversion.
  final expectedText = <String, String>{
    'legacy Delta JSON': legacyDeltaMarkdown,
    'markdown': markdown,
    "empty '[]'": '',
  };

  for (final profile in EditorToolbarProfile.values) {
    group('profile ${profile.name}', () {
      inputs.forEach((label, content) {
        testWidgets(
            'shows converted markdown for $label and does not fire onChanged '
            'on mount', (tester) async {
          var changeCount = 0;
          String? lastValue;

          await mountEditor(
            tester,
            NoteMarkdownEditor(
              initialContent: content,
              toolbar: profile,
              onChanged: (value) {
                changeCount++;
                lastValue = value;
              },
            ),
          );

          expect(find.byType(NoteMarkdownEditor), findsOneWidget);

          // The TextField holds the converted Markdown text.
          final field = tester.widget<TextField>(find.byType(TextField));
          expect(field.controller!.text, expectedText[label]);

          // onChanged must NOT fire merely from mounting / initial seeding.
          expect(
            changeCount,
            0,
            reason: 'onChanged fired $changeCount time(s) on mount '
                '(last value: $lastValue) for profile ${profile.name} '
                'with $label input',
          );
        });
      });
    });
  }

  testWidgets('typing fires onChanged with the current markdown text',
      (tester) async {
    var changeCount = 0;
    String? lastValue;

    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: '',
        toolbar: EditorToolbarProfile.full,
        onChanged: (value) {
          changeCount++;
          lastValue = value;
        },
      ),
    );

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pump();

    expect(changeCount, greaterThan(0));
    expect(lastValue, 'hello world');
  });

  testWidgets('bold toolbar button wraps the selection and fires onChanged',
      (tester) async {
    var changeCount = 0;
    String? lastValue;

    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: 'hello',
        toolbar: EditorToolbarProfile.full,
        onChanged: (value) {
          changeCount++;
          lastValue = value;
        },
      ),
    );

    // Select the whole word "hello".
    final field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    final baseline = changeCount;
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(lastValue, '**hello**');
    expect(field.controller!.text, '**hello**');
    expect(changeCount, greaterThan(baseline));
  });

  testWidgets(
      'Tab in the edit field inserts two spaces, fires onChanged, and does '
      'not move focus', (tester) async {
    var changeCount = 0;
    String? lastValue;

    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: 'hi',
        toolbar: EditorToolbarProfile.full,
        onChanged: (value) {
          changeCount++;
          lastValue = value;
        },
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));

    // Focus the field and place the caret at the end of "hi".
    await tester.tap(find.byType(TextField));
    await tester.pump();
    field.controller!.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    final focusedBefore = FocusManager.instance.primaryFocus;
    final baseline = changeCount;

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    // Two spaces were inserted at the caret and onChanged fired with the text.
    expect(field.controller!.text, 'hi  ');
    expect(lastValue, 'hi  ');
    expect(changeCount, greaterThan(baseline));
    // Caret sits directly after the inserted spaces.
    expect(field.controller!.selection.baseOffset, 4);
    // Tab did NOT traverse focus away from the field.
    expect(FocusManager.instance.primaryFocus, same(focusedBefore));
  });

  testWidgets('renders a trailing widget in the control bar', (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: '',
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
        trailing: const Text('TRAILING-MARKER'),
      ),
    );

    expect(find.text('TRAILING-MARKER'), findsOneWidget);
  });

  testWidgets('toggling to preview renders markdown and hides the TextField',
      (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
      ),
    );

    // Edit mode: TextField present, no rendered preview.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);

    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();

    // Preview mode: rendered Markdown present, TextField gone.
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
      'readOnly renders preview only — no TextField, no toolbar, no onChanged',
      (tester) async {
    var changeCount = 0;

    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        readOnly: true,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) => changeCount++,
      ),
    );

    expect(find.byType(NoteMarkdownEditor), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    // No toolbar / toggle controls in read-only mode.
    expect(find.byType(IconButton), findsNothing);
    expect(changeCount, 0);
  });

  testWidgets(
      'initiallyPreview: true with non-empty content starts in preview',
      (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        initiallyPreview: true,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
      ),
    );

    // Non-empty note opens rendered: preview present, editor field gone.
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  for (final entry in {'empty string': '', "empty '[]'": '[]'}.entries) {
    testWidgets(
        'initiallyPreview: true with ${entry.key} content starts in edit',
        (tester) async {
      await mountEditor(
        tester,
        NoteMarkdownEditor(
          initialContent: entry.value,
          initiallyPreview: true,
          toolbar: EditorToolbarProfile.full,
          onChanged: (_) {},
        ),
      );

      // Empty / new note opens ready to type: editor field present, no preview.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);
    });
  }

  testWidgets('initiallyPreview: false (default) starts in edit',
      (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('Ctrl+E toggles between edit and preview in both modes',
      (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
      ),
    );

    // Start in edit mode; focus the field so the shortcut can reach the handler.
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    // Ctrl+E: edit -> preview.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // Ctrl+E again from preview: preview -> edit. Works without a TextField
    // focused because the toggle is delivered by a global HardwareKeyboard
    // handler, not by a focus-subtree handler.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets(
      'Ctrl+E toggles even when no editor node is focused (global handler)',
      (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
      ),
    );

    // Start in edit mode WITHOUT focusing the field: the editor claims the
    // active-toggle slot on mount, so the global handler still fires.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);

    // A single Ctrl+E press must flip exactly once (edit -> preview): the
    // MarkdownBody appearing and the TextField disappearing proves one toggle
    // (a double toggle would land back in edit).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // Meta+E (macOS) exercises the same global path from preview -> edit.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });
}
