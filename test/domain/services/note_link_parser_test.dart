import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/services/note_link_parser.dart';

/// Parses [content] as if authored by note `source` unless told otherwise.
List<String> targetsIn(String content, {String source = 'source'}) =>
    NoteLinkParser.parse(sourceNoteId: source, content: content)
        .map((link) => link.targetNoteId)
        .toList();

void main() {
  group('noteIdFromHref', () {
    test('reads the id from the host', () {
      expect(NoteLinkParser.noteIdFromHref('notex://abc-123'), 'abc-123');
    });

    test('falls back to the path when there is no authority', () {
      expect(NoteLinkParser.noteIdFromHref('notex:/abc-123'), 'abc-123');
      expect(NoteLinkParser.noteIdFromHref('notex:abc-123'), 'abc-123');
    });

    test('rejects other schemes and junk', () {
      expect(NoteLinkParser.noteIdFromHref('https://example.com'), isNull);
      expect(NoteLinkParser.noteIdFromHref('notexx://abc'), isNull);
      expect(NoteLinkParser.noteIdFromHref('notex://'), isNull);
      expect(NoteLinkParser.noteIdFromHref(''), isNull);
      expect(NoteLinkParser.noteIdFromHref(null), isNull);
    });
  });

  group('parse — what counts as a link', () {
    test('finds an internal link and keeps its display text', () {
      final links = NoteLinkParser.parse(
        sourceNoteId: 'a',
        content: 'see [Hexagonal Architecture](notex://b) for context',
      );

      expect(links, hasLength(1));
      expect(links.single.sourceNoteId, 'a');
      expect(links.single.targetNoteId, 'b');
      expect(links.single.displayText, 'Hexagonal Architecture');
    });

    test('finds several distinct targets', () {
      expect(targetsIn('[x](notex://b) and [y](notex://c)'), ['b', 'c']);
    });

    test('ignores external links', () {
      expect(targetsIn('[docs](https://flutter.dev) [x](notex://b)'), ['b']);
    });

    test('tolerates a link title after the href', () {
      expect(targetsIn('[x](notex://b "a title")'), ['b']);
    });

    test('handles empty display text', () {
      final links = NoteLinkParser.parse(
        sourceNoteId: 'a',
        content: '[](notex://b)',
      );
      expect(links.single.displayText, '');
    });

    test('returns nothing for empty or link-free content', () {
      expect(targetsIn(''), isEmpty);
      expect(targetsIn('just some prose'), isEmpty);
    });
  });

  group('parse — code is documentation, not linkage', () {
    test('ignores links inside a fenced block', () {
      expect(
        targetsIn('before\n```\n[x](notex://b)\n```\nafter'),
        isEmpty,
      );
    });

    test('ignores links inside a tilde-fenced block', () {
      expect(targetsIn('~~~\n[x](notex://b)\n~~~'), isEmpty);
    });

    test('ignores links inside inline code', () {
      expect(targetsIn('write `[x](notex://b)` to link'), isEmpty);
    });

    test('still finds links outside the fence', () {
      expect(
        targetsIn('[real](notex://b)\n```\n[fake](notex://c)\n```'),
        ['b'],
      );
    });

    test('an unterminated fence swallows the rest, like a renderer would', () {
      expect(targetsIn('```\n[x](notex://b)\nno closing fence'), isEmpty);
    });
  });

  group('parse — graph invariants', () {
    test('a note is never its own backlink', () {
      expect(targetsIn('[self](notex://a)', source: 'a'), isEmpty);
    });

    test('repeated links to one target collapse to a single edge', () {
      expect(targetsIn('[one](notex://b) [two](notex://b)'), ['b']);
    });

    test('the first display text wins when a target repeats', () {
      final links = NoteLinkParser.parse(
        sourceNoteId: 'a',
        content: '[first](notex://b) [second](notex://b)',
      );
      expect(links, hasLength(1));
      expect(links.single.displayText, 'first');
    });
  });
}
