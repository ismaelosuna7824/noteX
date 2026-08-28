import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/services/markdown_task_toggle.dart';
import 'package:notex/presentation/widgets/markdown/markdown_list.dart';
import 'package:notex/presentation/widgets/markdown/notex_markdown_view.dart';

/// Every string the preview actually paints, flattened.
///
/// The renderer composes an item out of nested spans, so the visible sentence
/// usually is not any single widget's `data`.
List<String> _renderedText(WidgetTester tester) {
  final out = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    out.add(((element.widget as RichText).text).toPlainText());
  }
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final value = text.data ?? text.textSpan?.toPlainText();
    if (value != null) out.add(value);
  }
  return out;
}

bool _renders(WidgetTester tester, String needle) =>
    _renderedText(tester).any((line) => line.contains(needle));

Future<void> _pump(
  WidgetTester tester,
  String markdown, {
  ValueChanged<int>? onToggleTask,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NoteXMarkdownView(
            data: markdown,
            onToggleTask: onToggleTask,
            style: const NoteXMarkdownStyle(
              isDark: true,
              baseFontSize: 16,
              lineHeight: 1.5,
              textColor: Colors.white,
              accentColor: Colors.teal,
              surfaceColor: Colors.black,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// How many checkboxes the preview drew, counted the way the reader would.
int _checkboxCount(WidgetTester tester) {
  int n = 0;
  while (find.byKey(markdownTaskKey(n)).evaluate().isNotEmpty) {
    n++;
  }
  return n;
}

void main() {
  group('the tree', () {
    const nested = '- [ ] one\n  - [x] two\n    - [ ] three\n- [ ] four';

    testWidgets('renders every item at every depth', (tester) async {
      await _pump(tester, nested);
      for (final item in ['one', 'two', 'three', 'four']) {
        expect(_renders(tester, item), isTrue, reason: 'missing "$item"');
      }
    });

    testWidgets('offers a fold control only where there is a branch',
        (tester) async {
      await _pump(tester, nested);
      // Items 0 and 1 have children; 2 and 3 are leaves.
      expect(find.byKey(markdownFoldKey(0)), findsOneWidget);
      expect(find.byKey(markdownFoldKey(1)), findsOneWidget);
      expect(find.byKey(markdownFoldKey(2)), findsNothing);
      expect(find.byKey(markdownFoldKey(3)), findsNothing);
    });

    testWidgets('folding an item hides the whole branch under it',
        (tester) async {
      await _pump(tester, nested);
      expect(_renders(tester, 'three'), isTrue);

      await tester.tap(find.byKey(markdownFoldKey(0)));
      await tester.pumpAndSettle();

      // The branch goes, and everything outside it stays.
      expect(_renders(tester, 'two'), isFalse);
      expect(_renders(tester, 'three'), isFalse);
      expect(_renders(tester, 'one'), isTrue);
      expect(_renders(tester, 'four'), isTrue);
    });

    testWidgets('folding is reversible', (tester) async {
      await _pump(tester, nested);
      await tester.tap(find.byKey(markdownFoldKey(0)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(markdownFoldKey(0)));
      await tester.pumpAndSettle();
      expect(_renders(tester, 'three'), isTrue);
    });

    testWidgets('a plain nested list renders too', (tester) async {
      await _pump(tester, '- one\n  - two\n    - three');
      for (final item in ['one', 'two', 'three']) {
        expect(_renders(tester, item), isTrue, reason: 'missing "$item"');
      }
      expect(find.byKey(markdownFoldKey(0)), findsOneWidget);
    });

    testWidgets('an ordered list numbers from its start attribute',
        (tester) async {
      await _pump(tester, '3. three\n4. four');
      expect(_renders(tester, '3.'), isTrue);
      expect(_renders(tester, '4.'), isTrue);
    });
  });

  group('checkboxes', () {
    testWidgets('draws one box per task and no more', (tester) async {
      await _pump(tester, '- [ ] one\n- [x] two\n- three');
      expect(_checkboxCount(tester), 2);
    });

    testWidgets('reports the index of the box that was pressed',
        (tester) async {
      final pressed = <int>[];
      await _pump(
        tester,
        '- [ ] one\n  - [x] two\n- [ ] three',
        onToggleTask: pressed.add,
      );

      await tester.tap(find.byKey(markdownTaskKey(1)));
      await tester.pump();
      expect(pressed, [1]);

      await tester.tap(find.byKey(markdownTaskKey(2)));
      await tester.pump();
      expect(pressed, [1, 2]);
    });

    testWidgets('still draws, and does not blow up, with no handler',
        (tester) async {
      await _pump(tester, '- [ ] one');
      expect(find.byKey(markdownTaskKey(0)), findsOneWidget);
      await tester.tap(find.byKey(markdownTaskKey(0)));
      await tester.pump();
    });
  });

  group('loose and tight lists', () {
    // The parser wraps item content in a `<p>` when a list is loose and leaves
    // it bare when the list is tight, and one blank line anywhere flips the
    // whole list. The two have to render the same or a checklist changes shape
    // when an unrelated line is added to it.
    const tight = '- [ ] one\n- [x] two';
    const loose = '- [ ] one\n\n- [x] two';

    testWidgets('both draw the same checkboxes', (tester) async {
      await _pump(tester, tight);
      expect(_checkboxCount(tester), 2);

      await _pump(tester, loose);
      expect(_checkboxCount(tester), 2);
    });

    testWidgets('both report the same indices', (tester) async {
      final pressed = <int>[];
      await _pump(tester, loose, onToggleTask: pressed.add);
      await tester.tap(find.byKey(markdownTaskKey(1)));
      await tester.pump();
      expect(pressed, [1]);
    });
  });

  group('the renderer and the toggler agree', () {
    // This is the invariant the whole feature rests on. The preview knows only
    // "this is the nth checkbox"; MarkdownTaskToggle knows only "the nth task
    // line". If those two ever count differently, a tap edits the wrong line —
    // silently, and in the reader's own notes.
    const documents = <String>[
      '- [ ] one\n- [x] two',
      '- [ ] one\n  - [x] two\n    - [ ] three',
      '- [ ] one\n\n- [x] two',
      '# Title\n\n- [ ] one\n\nProse.\n\n- [x] two',
      '1. [ ] one\n2. [x] two',
      '- [ ] real\n\n```\n- [ ] example\n```\n\n- [ ] also real',
      '- plain\n- [ ] task\n- plain again',
    ];

    for (final source in documents) {
      testWidgets('same count for ${source.replaceAll('\n', ' / ')}',
          (tester) async {
        await _pump(tester, source);
        expect(
          _checkboxCount(tester),
          MarkdownTaskToggle.taskLines(source).length,
        );
      });
    }
  });
}
