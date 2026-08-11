import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/services/mention_trigger.dart';
import 'package:notex/domain/services/note_link_parser.dart';

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

    test('round-trips the href the mention picker actually writes', () {
      // Pins the read side to the write side: if MentionTrigger ever changes
      // the href it emits, this fails instead of links silently going dead.
      expect(
        NoteLinkParser.noteIdFromHref(MentionTrigger.linkHref('abc-123')),
        'abc-123',
      );
    });
  });
}
