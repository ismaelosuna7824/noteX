import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/services/mention_trigger.dart';

/// Detects the mention at the caret marked by `|` in [textWithCaret].
MentionQuery? detectAt(String textWithCaret) {
  final caret = textWithCaret.indexOf('|');
  return MentionTrigger.detect(
    text: textWithCaret.replaceFirst('|', ''),
    caret: caret,
  );
}

void main() {
  group('detect — when a mention opens', () {
    test('an @ at the very start opens an empty query', () {
      final query = detectAt('@|');
      expect(query, isNotNull);
      expect(query!.query, '');
      expect(query.start, 0);
      expect(query.end, 1);
    });

    test('captures what has been typed after the @', () {
      final query = detectAt('see @hexa|');
      expect(query!.query, 'hexa');
      expect(query.start, 4);
      expect(query.end, 9);
    });

    test('opens after a newline, not just a space', () {
      expect(detectAt('line one\n@ar|')!.query, 'ar');
    });

    test('reads the token at the caret, ignoring text after it', () {
      expect(detectAt('@arch| and more prose')!.query, 'arch');
    });
  });

  group('detect — when it must stay closed', () {
    test('an email address is not a mention', () {
      expect(detectAt('write to user@example|'), isNull);
    });

    test('an @ glued to a word is not a mention', () {
      expect(detectAt('foo@bar|'), isNull);
    });

    test('a space after the @ abandons the mention', () {
      expect(detectAt('@arch and|'), isNull);
    });

    test('plain prose with no @ has no mention', () {
      expect(detectAt('just some words|'), isNull);
    });

    test('a caret before the @ sees nothing', () {
      expect(detectAt('|@arch'), isNull);
    });

    test('gives up once the query grows past a title fragment', () {
      final long = 'x' * (MentionTrigger.maxQueryLength + 5);
      expect(detectAt('@$long|'), isNull);
    });

    test('guards out-of-range carets', () {
      expect(MentionTrigger.detect(text: 'abc', caret: -1), isNull);
      expect(MentionTrigger.detect(text: 'abc', caret: 99), isNull);
    });
  });

  group('complete — building the link', () {
    MentionInsertion completeIn(String textWithCaret, String display) {
      final caret = textWithCaret.indexOf('|');
      final text = textWithCaret.replaceFirst('|', '');
      return MentionTrigger.complete(
        text: text,
        trigger: MentionTrigger.detect(text: text, caret: caret)!,
        noteId: 'abc-123',
        displayText: display,
      );
    }

    test('replaces the composing token with a Markdown link', () {
      final result = completeIn('see @hexa|', 'Hexagonal Architecture');
      expect(result.text, 'see [Hexagonal Architecture](notex://abc-123)');
    });

    test('leaves the caret just past the inserted link', () {
      final result = completeIn('@h|', 'Note');
      expect(result.caret, result.text.length);
      expect(result.text, '[Note](notex://abc-123)');
    });

    test('keeps text that follows the mention intact', () {
      final caret = 'a @h'.length;
      const text = 'a @h and then some';
      final result = MentionTrigger.complete(
        text: text,
        trigger: MentionTrigger.detect(text: text, caret: caret)!,
        noteId: 'x',
        displayText: 'N',
      );
      expect(result.text, 'a [N](notex://x) and then some');
    });

    test('neutralises brackets that would end the label early', () {
      final result = completeIn('@h|', 'Draft [v2]');
      expect(result.text, '[Draft (v2)](notex://abc-123)');
    });

    test('flattens newlines in the title', () {
      final result = completeIn('@h|', 'Multi\nline   title');
      expect(result.text, '[Multi line title](notex://abc-123)');
    });

    test('an untitled note still gets something clickable', () {
      final result = completeIn('@h|', '   ');
      expect(result.text, '[Untitled note](notex://abc-123)');
    });
  });

  test('linkHref matches the scheme the parser reads back', () {
    expect(MentionTrigger.linkHref('abc-123'), 'notex://abc-123');
  });
}
