import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/markdown/markdown_blocks.dart';
import 'package:notex/presentation/widgets/markdown/notex_markdown_view.dart';

/// Every string the preview actually paints, flattened.
///
/// Assertions go through this rather than through `find.text`, because the
/// renderer composes a paragraph out of nested spans — the visible sentence
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
  ValueChanged<String>? onTapLink,
  bool isDark = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NoteXMarkdownView(
            data: markdown,
            onTapLink: onTapLink,
            style: NoteXMarkdownStyle(
              isDark: isDark,
              baseFontSize: 16,
              lineHeight: 1.5,
              textColor: isDark ? Colors.white : Colors.black,
              accentColor: const Color(0xFFD9A892),
              surfaceColor: isDark ? const Color(0xFF16161B) : Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('behaviour that existing notes depend on', () {
    testWidgets('a single newline stays a line break', (tester) async {
      // The old preview passed softLineBreak: true, so one Enter was one
      // visible break. Every note in every library was written against that.
      // Plain CommonMark would collapse this pair into one line.
      await _pump(tester, 'first line\nsecond line');

      expect(_renders(tester, 'first line\nsecond line'), isTrue);
    });

    testWidgets('a note link reports its raw href, scheme intact',
        (tester) async {
      String? tapped;
      await _pump(
        tester,
        '[Ideas](notex://abc-123)',
        onTapLink: (href) => tapped = href,
      );

      // tapOnText targets the glyphs themselves. A plain tap lands on the
      // centre of the paragraph, which is only the link when the link is the
      // whole paragraph.
      await tester.tapOnText(find.textRange.ofSubstring('Ideas'));
      await tester.pump();

      // The href must arrive unparsed: NoteLinkParser is the single place that
      // decides what a notex:// URL means.
      expect(tapped, 'notex://abc-123');
    });

    testWidgets('tables, task lists and strikethrough still render',
        (tester) async {
      await _pump(tester, '''
| a | b |
|---|---|
| 1 | 2 |

- [x] done
- [ ] pending

~~struck~~
''');

      expect(_renders(tester, 'a'), isTrue);
      expect(_renders(tester, 'done'), isTrue);
      expect(_renders(tester, 'struck'), isTrue);
      expect(find.byType(Table), findsOneWidget);
    });
  });

  group('features the old renderer dropped', () {
    testWidgets('an alert renders as a callout, not a literal marker',
        (tester) async {
      await _pump(tester, '> [!WARNING]\n> Careful here.');

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(_renders(tester, 'Careful here.'), isTrue);
      // The old renderer printed this verbatim inside a blockquote.
      expect(_renders(tester, '[!WARNING]'), isFalse);
    });

    testWidgets('inline formatting survives inside an alert', (tester) async {
      // The reason the preview moved renderers at all: the previous builder
      // API discarded a block's already-built children, so bold and links
      // inside a callout would have had to be re-implemented by hand.
      String? tapped;
      await _pump(
        tester,
        '> [!NOTE]\n> See **bold** and [a link](notex://xyz).',
        onTapLink: (href) => tapped = href,
      );

      expect(_renders(tester, 'bold'), isTrue);

      await tester.tapOnText(find.textRange.ofSubstring('a link'));
      await tester.pump();
      expect(tapped, 'notex://xyz');
    });

    testWidgets('every alert kind gets its own icon', (tester) async {
      for (final kind in AlertKind.values) {
        await _pump(tester, '> [!${kind.slug.toUpperCase()}]\n> body');
        expect(find.byIcon(kind.icon), findsOneWidget, reason: kind.slug);
      }
    });

    testWidgets('emoji shortcodes become emoji', (tester) async {
      await _pump(tester, 'ship it :rocket:');

      expect(_renders(tester, '🚀'), isTrue);
      expect(_renders(tester, ':rocket:'), isFalse);
    });

    testWidgets('a footnote separates its definition from the body',
        (tester) async {
      await _pump(tester, 'Claim[^1].\n\n[^1]: The evidence.');

      expect(_renders(tester, 'Claim'), isTrue);
      expect(_renders(tester, 'The evidence.'), isTrue);
      // The marker is a superscript, not a number glued to the word.
      expect(find.byType(Transform), findsWidgets);
    });
  });

  group('mermaid', () {
    testWidgets('a mermaid fence renders as a diagram', (tester) async {
      await _pump(tester, '''
```mermaid
flowchart TD
    A[Start] --> B[End]
```
''');

      expect(find.byType(MermaidBlock), findsOneWidget);
    });

    testWidgets('an ordinary fence is still code, not a diagram',
        (tester) async {
      await _pump(tester, '```dart\nvoid main() {}\n```');

      expect(find.byType(MermaidBlock), findsNothing);
      expect(_renders(tester, 'void main()'), isTrue);
    });

    testWidgets('the inline diagram never captures a drag', (tester) async {
      // A pannable canvas inline would eat the drag meant to scroll the note,
      // leaving a dead zone in the middle of the reader's own document. Zoom
      // lives in the viewer precisely so this stays true.
      await _pump(tester, '''
```mermaid
flowchart TD
    A[Start] --> B[End]
```
''');

      expect(
        find.descendant(
          of: find.byType(MermaidBlock),
          matching: find.byType(InteractiveViewer),
        ),
        findsNothing,
      );
    });

    testWidgets('without the native renderer, the source is shown', (tester) async {
      // flutter_test builds no app bundle, so merman's library is absent. That
      // path must degrade to the author's text, which is the same fallback a
      // half-typed diagram relies on.
      await _pump(tester, '''
```mermaid
flowchart TD
    A[Start] --> B[End]
```
''');

      expect(find.byType(MermaidBlock), findsOneWidget);
      expect(_renders(tester, 'flowchart TD'), isTrue);
    });

    // The viewer is pumped directly: opening it needs a rendered diagram, and
    // the native renderer is not present here. Its zoom behaviour is worth
    // pinning regardless of what produced the drawing.
    Future<void> pumpViewer(WidgetTester tester) async {
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 60">'
          '<rect width="100" height="60" fill="#888"/></svg>';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MermaidViewer(svg: svg, isDark: true)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the viewer opens at 1:1 and says so', (tester) async {
      await pumpViewer(tester);

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(_renders(tester, '100%'), isTrue);
    });

    testWidgets('zooming in reports the new scale and reset returns to 1:1',
        (tester) async {
      await pumpViewer(tester);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(_renders(tester, '130%'), isTrue);

      await tester.tap(find.byIcon(Icons.fit_screen_rounded));
      await tester.pumpAndSettle();
      expect(_renders(tester, '100%'), isTrue);
    });

    testWidgets('unparseable mermaid falls back to showing the source',
        (tester) async {
      // Someone typing a diagram is, for most keystrokes, holding something
      // that does not parse yet. That has to show their text back, not an
      // empty box.
      await _pump(tester, '```mermaid\nnot a real diagram at all\n```');
      await tester.pumpAndSettle();

      expect(_renders(tester, 'not a real diagram at all'), isTrue);
    });
  });
}
