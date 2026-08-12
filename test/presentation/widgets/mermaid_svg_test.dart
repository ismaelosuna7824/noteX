import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/markdown/mermaid_svg.dart';
import 'package:xml/xml.dart';

/// A real Mermaid sequence diagram, straight out of the renderer.
///
/// A hand-written sample would only prove the transformer handles the SVG we
/// imagined. The failures that mattered here — a line that says `stroke="none"`
/// and is rescued by the sheet — were things nobody would have thought to
/// invent.
String get _fixture =>
    File('test/fixtures/mermaid_sequence.svg').readAsStringSync();

/// A flowchart, where the stylesheet leans on ancestry the sequence one did not.
String get _flowchart =>
    File('test/fixtures/mermaid_flowchart.svg').readAsStringSync();

XmlDocument _flattened() => XmlDocument.parse(flattenMermaidSvg(_fixture));

Iterable<XmlElement> _withClass(XmlDocument doc, String className) =>
    doc.rootElement.descendantElements.where((e) =>
        (e.getAttribute('class') ?? '').split(' ').contains(className));

void main() {
  group('the stylesheet', () {
    test('a stroke the sheet supplied beats the attribute that denied it', () {
      // The whole reason arrows were invisible: the element carries
      // stroke="none" and only `.messageLine0{stroke:#333}` saves it, because a
      // stylesheet rule outranks a presentation attribute.
      expect(_fixture, contains('class="messageLine0"'));
      expect(_fixture, contains('stroke="none"'));

      final lines = _withClass(_flattened(), 'messageLine0');
      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line.getAttribute('stroke'), isNot('none'),
            reason: 'a message line left with stroke:none draws nothing');
      }
    });

    test('the element\'s own inline style still wins', () {
      // Message lines are `style="fill:none"`, which must survive: filling a
      // stroked line turns an arrow into a solid wedge.
      for (final line in _withClass(_flattened(), 'messageLine0')) {
        expect(line.getAttribute('fill'), 'none');
      }
    });

    test('nothing is left depending on a <style> block', () {
      final flattened = _flattened();

      expect(
        flattened.rootElement.descendantElements
            .where((e) => e.localName == 'style'),
        isEmpty,
        reason: 'a surviving sheet is a second source of truth for paint',
      );
      expect(
        flattened.rootElement.descendantElements
            .where((e) => e.getAttribute('style') != null),
        isEmpty,
      );
    });

    test('dashed messages keep their dashes', () {
      final dashed = _flattened()
          .rootElement
          .descendantElements
          .where((e) => e.getAttribute('stroke-dasharray') != null);

      expect(dashed, isNotEmpty,
          reason: 'a reply arrow that loses its dashes reads as a request');
    });

    test('a rule for a descendant does not repaint its ancestor', () {
      // `#merman text.actor>tspan{fill:black}` means the tspan inside an actor
      // label. Reading the first class out of that tail instead of its final
      // compound applied it to everything classed `actor` — including the
      // participant boxes, which came out solid black with their labels lost
      // inside them.
      final boxes = _withClass(_flattened(), 'actor')
          .where((e) => e.localName == 'rect');

      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        expect(box.getAttribute('fill'), isNot('black'));
      }
    });

    test('the label inside the box is still legible against it', () {
      final flattened = _flattened();
      final label = flattened.rootElement.descendantElements
          .firstWhere((e) => e.localName == 'text');
      final glyphs = label.childElements.where((e) => e.localName == 'tspan');

      expect(glyphs, isNotEmpty);
      for (final glyph in glyphs) {
        expect(glyph.getAttribute('fill'), isNot(label.getAttribute('fill')),
            reason: 'a label painted its own box colour is invisible');
      }
    });
  });

  group('a flowchart, where the ancestry matters', () {
    test('an edge stays a line instead of becoming a filled wedge', () {
      // `#merman .root .anchor path{fill:#333!important}` describes a path
      // inside an anchor. Matched on its tail alone it became a rule for every
      // path, and being !important it beat `.flowchart-link{fill:none}` — so
      // each edge was flood-filled and read as a thick black wedge.
      final out = XmlDocument.parse(flattenMermaidSvg(_flowchart));
      final edges = out.rootElement.descendantElements.where((e) =>
          e.localName == 'path' &&
          (e.getAttribute('class') ?? '').contains('flowchart-link'));

      expect(edges, isNotEmpty);
      for (final edge in edges) {
        expect(edge.getAttribute('fill'), 'none');
        expect(edge.getAttribute('stroke'), isNotNull);
      }
    });

    test('CSS cascade keywords never reach an attribute', () {
      // `stroke:revert` is a cascade instruction, not a colour. Copied out
      // verbatim it is simply invalid paint.
      final out = XmlDocument.parse(flattenMermaidSvg(_flowchart));

      expect(
        out.rootElement.descendantElements.where((e) => e.attributes.any((a) =>
            const {'revert', 'unset', 'initial', 'inherit'}
                .contains(a.value.toLowerCase()))),
        isEmpty,
      );
    });
  });

  group('text placement', () {
    test('a line advance becomes a coordinate', () {
      // Mermaid gives the <text> no y at all and advances each line with
      // dy="1em". A renderer that ignores dy stacks every line on the group's
      // origin, which is how branch labels ended up floating above their own
      // boxes instead of sitting inside them.
      expect(_fixture, contains('dy='));

      final flattened = _flattened();
      final spans = flattened.rootElement.descendantElements
          .where((e) => e.localName == 'tspan');

      expect(spans, isNotEmpty);
      for (final span in spans) {
        expect(span.getAttribute('dy'), isNull);
        expect(span.getAttribute('y'), isNotNull);
      }
    });

    test('successive lines land at successive heights', () {
      // A multi-line label whose lines all share one y is a single illegible
      // smudge.
      final multi = XmlDocument.parse(flattenMermaidSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" font-size="10">'
        '<text y="4"><tspan dy="1em">one</tspan>'
        '<tspan dy="1em">two</tspan></text></svg>',
      ));

      final ys = multi.rootElement.descendantElements
          .where((e) => e.localName == 'tspan')
          .map((e) => double.parse(e.getAttribute('y')!))
          .toList();

      expect(ys, [14, 24]);
    });

    test('a middle baseline becomes an offset instead of an attribute', () {
      // `dominant-baseline="middle"` asks for the text to be centred on its y.
      // Ignored, that y is read as the baseline and the glyphs ride above it —
      // which clipped the first line of every note box against its own top
      // edge.
      final out = XmlDocument.parse(flattenMermaidSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" font-size="10">'
        '<text y="100" dominant-baseline="middle"><tspan>x</tspan></text>'
        '</svg>',
      ));

      final span = out.rootElement.descendantElements
          .firstWhere((e) => e.localName == 'tspan');
      final text = out.rootElement.descendantElements
          .firstWhere((e) => e.localName == 'text');

      expect(double.parse(span.getAttribute('y')!), greaterThan(100));
      expect(text.getAttribute('dominant-baseline'), isNull,
          reason: 'a renderer that does honour it would shift twice');
    });
  });

  group('note boxes', () {
    test('the lines end up centred in the box drawn for them', () {
      // Merman sizes a note box with more padding than its text block uses and
      // then places the text from the top: the lines sit high, the space is
      // left underneath, and the first line grazes the top border. Real
      // numbers from a three-line note — box 75..152, lines centred on 99.
      final out = XmlDocument.parse(flattenMermaidSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" font-size="16">'
        '<rect class="note" x="50" y="75" width="250" height="77"/>'
        '<text class="noteText" x="175" y="80"><tspan>one</tspan></text>'
        '<text class="noteText" x="175" y="99"><tspan>two</tspan></text>'
        '<text class="noteText" x="175" y="118"><tspan>three</tspan></text>'
        '</svg>',
      ));

      final ys = out.rootElement.descendantElements
          .where((e) => e.localName == 'text')
          .map((e) => double.parse(e.getAttribute('y')!))
          .toList();

      // Box centre is 113.5; the block must straddle it.
      final blockCentre = (ys.first + ys.last) / 2;
      expect(blockCentre, closeTo(113.5, 0.01));
      // Spacing is untouched — only the block as a whole moves.
      expect(ys[1] - ys[0], closeTo(19, 0.01));
    });

    test('a note does not adopt the text of another one', () {
      final out = XmlDocument.parse(flattenMermaidSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" font-size="16">'
        '<rect class="note" x="0" y="0" width="100" height="40"/>'
        '<text class="noteText" x="50" y="5"><tspan>near</tspan></text>'
        '<rect class="note" x="400" y="0" width="100" height="40"/>'
        '<text class="noteText" x="450" y="5"><tspan>far</tspan></text>'
        '</svg>',
      ));

      final byText = {
        for (final e in out.rootElement.descendantElements
            .where((e) => e.localName == 'text'))
          e.innerText.trim(): double.parse(e.getAttribute('y')!),
      };

      // Each is centred in its own box, so both land on the same line — and
      // neither was dragged across to the other.
      expect(byText['near'], closeTo(20, 0.01));
      expect(byText['far'], closeTo(20, 0.01));
    });
  });

  group('the background', () {
    test('is dropped, and nothing is painted in its place', () {
      // `background-color` on the root is CSS, which a browser honours and a
      // plain SVG renderer ignores. It is removed rather than left, so a
      // renderer that does honour it cannot paint a slab the app never asked
      // for — and nothing replaces it, because the diagram sits inside the
      // block's own card, which already has the ground and the rounded
      // corners. An opaque rectangle inside that card reads as a hard slab.
      expect(_fixture, contains('background-color'));

      final flattened = _flattened();

      expect(flattened.rootElement.getAttribute('style'), isNull);
      expect(
        flattened.toXmlString(),
        isNot(contains('background-color')),
      );
      expect(flattened.rootElement.childElements.first.localName, isNot('rect'),
          reason: 'a background rect would square off the card it sits in');
    });
  });

  group('arrowheads', () {
    test('every marker reference becomes something drawn', () {
      expect(_fixture, contains('marker-end='));

      final flattened = _flattened();

      expect(
        flattened.rootElement.descendantElements
            .where((e) => e.getAttribute('marker-end') != null),
        isEmpty,
        reason: 'no Flutter renderer draws <marker>, so none may remain',
      );

      final heads = flattened.rootElement.descendantElements.where((e) =>
          e.localName == 'g' &&
          (e.getAttribute('transform') ?? '').contains('rotate'));
      expect(heads, isNotEmpty);
    });

    test('a head points along its own line, not at a fixed angle', () {
      // Two arrows in this diagram run in opposite directions; a transformer
      // that ignored direction would give them the same rotation.
      final rotations = _flattened()
          .rootElement
          .descendantElements
          .where((e) => e.localName == 'g')
          .map((e) => RegExp(r'rotate\((-?[\d.]+)\)')
              .firstMatch(e.getAttribute('transform') ?? '')
              ?.group(1))
          .whereType<String>()
          .toSet();

      expect(rotations.length, greaterThan(1),
          reason: 'every arrowhead ended up pointing the same way');
      expect(rotations, contains('180'),
          reason: 'a right-to-left message must point left');
    });

    test('a head takes the colour of the line it ends', () {
      final coloured = _flattened()
          .rootElement
          .descendantElements
          .where((e) =>
              e.localName == 'g' &&
              (e.getAttribute('transform') ?? '').contains('rotate'))
          .where((e) => e.getAttribute('fill') != null);

      expect(coloured, isNotEmpty,
          reason: 'an uncoloured head falls back to black on a pale arrow');
    });
  });

  test('the result is still valid SVG', () {
    expect(() => XmlDocument.parse(flattenMermaidSvg(_fixture)), returnsNormally);
  });

  test('an SVG with no stylesheet passes through unharmed', () {
    const plain =
        '<svg xmlns="http://www.w3.org/2000/svg"><rect width="4" height="4" '
        'fill="#f00"/></svg>';

    final out = XmlDocument.parse(flattenMermaidSvg(plain));
    final rect = out.rootElement.descendantElements.first;
    expect(rect.getAttribute('fill'), '#f00');
  });
}
