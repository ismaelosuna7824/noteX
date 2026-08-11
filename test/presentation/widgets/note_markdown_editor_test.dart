import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/markdown/notex_markdown_view.dart';
import 'package:notex/presentation/widgets/note_markdown_editor.dart';

void main() {
  /// Pumps [child] inside a minimal MaterialApp shell and settles it.
  Future<void> mountEditor(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        // Toolbar buttons are Material inkwells, and loading the ink sparkle
        // shader throws under a Flutter SDK whose shaders were compiled for
        // Vulkan only — the splash is incidental to every case here, so it is
        // switched off rather than left to decide whether the suite runs.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
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
    expect(find.byType(NoteXMarkdownView), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();

    // Preview mode: rendered Markdown present, TextField gone.
    expect(find.byType(NoteXMarkdownView), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('renders a fenced code block as a full-width box in preview',
      (tester) async {
    const withCodeBlock = 'Intro line\n\n```\nconst x = 1;\n```';

    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: withCodeBlock,
        readOnly: true,
        toolbar: EditorToolbarProfile.none,
        onChanged: (_) {},
      ),
    );

    // The custom `pre` builder renders the code text (trailing newline stripped)
    // inside a Container whose width fills the available preview width.
    final codeFinder = find.text('const x = 1;');
    expect(codeFinder, findsOneWidget);

    final box = tester.getSize(
      find.ancestor(of: codeFinder, matching: find.byType(Container)).first,
    );
    // 800px shell minus the preview's 16px padding on each side.
    expect(box.width, 800 - 32);
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
    expect(find.byType(NoteXMarkdownView), findsOneWidget);
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
    expect(find.byType(NoteXMarkdownView), findsOneWidget);
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
      expect(find.byType(NoteXMarkdownView), findsNothing);
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
    expect(find.byType(NoteXMarkdownView), findsNothing);
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

    expect(find.byType(NoteXMarkdownView), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // Ctrl+E again from preview: preview -> edit. Works without a TextField
    // focused because the toggle is delivered by a global HardwareKeyboard
    // handler, not by a focus-subtree handler.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(NoteXMarkdownView), findsNothing);
  });

  testWidgets('Ctrl+Shift+E toggles the side-by-side split view',
      (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
      ),
    );

    // Start in edit mode: field only, no live preview.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(NoteXMarkdownView), findsNothing);

    // Ctrl+Shift+E: edit -> split. Both surfaces are on screen at once.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(NoteXMarkdownView), findsOneWidget);

    // Ctrl+Shift+E again: split -> edit, collapsing back to the field only.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(NoteXMarkdownView), findsNothing);
  });

  testWidgets('initialViewMode: split opens directly in the split view',
      (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        initialViewMode: EditorViewMode.split,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
      ),
    );

    // Both surfaces are on screen at once — the editor restored the split mode
    // instead of the edit/preview default.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(NoteXMarkdownView), findsOneWidget);
  });

  testWidgets('initialViewMode: preview downgrades to edit on an empty note',
      (tester) async {
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: '',
        initialViewMode: EditorViewMode.preview,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
      ),
    );

    // A new/empty note must stay typable even when preview was requested.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(NoteXMarkdownView), findsNothing);
  });

  testWidgets('onViewModeChanged fires with the new mode on every toggle',
      (tester) async {
    final modes = <EditorViewMode>[];
    await mountEditor(
      tester,
      NoteMarkdownEditor(
        initialContent: markdown,
        toolbar: EditorToolbarProfile.full,
        onChanged: (_) {},
        onViewModeChanged: modes.add,
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    // Ctrl+Shift+E: edit -> split.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    // Ctrl+E: split -> preview.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(modes, [EditorViewMode.split, EditorViewMode.preview]);
  });

  testWidgets('EditorViewModeName.fromName round-trips and guards bad input',
      (tester) async {
    for (final mode in EditorViewMode.values) {
      expect(EditorViewModeName.fromName(mode.name), mode);
    }
    expect(EditorViewModeName.fromName('garbage'), EditorViewMode.edit);
    expect(EditorViewModeName.fromName(null), EditorViewMode.edit);
  });

  testWidgets(
      'autofocus editor claims the toggle slot on mount even when another '
      'editor already holds it', (tester) async {
    // Regression: opening the main editor in edit/split (which do not
    // auto-focus a surface) must still grab Cmd/Ctrl+E without a click, even
    // though the list-preview editor mounted first already holds the slot.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // First editor claims the slot on mount (slot was null).
              Expanded(
                child: NoteMarkdownEditor(
                  initialContent: 'AAA first',
                  onChanged: (_) {},
                ),
              ),
              // Primary editor: mounts second, opens in edit, and must steal
              // the slot via autofocus despite the first editor holding it.
              Expanded(
                child: NoteMarkdownEditor(
                  initialContent: 'BBB second',
                  initialViewMode: EditorViewMode.edit,
                  autofocus: true,
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Both editors start in edit → two fields, no rendered preview.
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(NoteXMarkdownView), findsNothing);

    // Ctrl+E WITHOUT tapping anything: only the autofocus editor should flip
    // (edit -> preview), proving it owns the slot. Its field is replaced by a
    // NoteXMarkdownView; the first editor's field stays put.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('AAA first'), findsOneWidget);
    expect(find.byType(NoteXMarkdownView), findsOneWidget);
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
    expect(find.byType(NoteXMarkdownView), findsNothing);

    // A single Ctrl+E press must flip exactly once (edit -> preview): the
    // NoteXMarkdownView appearing and the TextField disappearing proves one toggle
    // (a double toggle would land back in edit).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.byType(NoteXMarkdownView), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // Meta+E (macOS) exercises the same global path from preview -> edit.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(NoteXMarkdownView), findsNothing);
  });
}
