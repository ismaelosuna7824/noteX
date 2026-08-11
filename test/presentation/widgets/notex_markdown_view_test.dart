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
