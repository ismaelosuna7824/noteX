import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/note.dart';

/// Builds a bare note with the given [content] for content-getter tests.
Note noteWith(String content) => Note(
      id: 'test-id',
      title: 'Test',
      content: content,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('Note content — Delta (legacy) format', () {
    test('empty Delta "[]" is empty', () {
      final note = noteWith('[]');
      expect(note.isEmpty, isTrue);
      expect(note.wordCount, 0);
      expect(note.plainTextPreview, '');
    });

    test('whitespace-only Delta is empty', () {
      final note = noteWith('[{"insert":"\\n"}]');
      expect(note.isEmpty, isTrue);
      expect(note.wordCount, 0);
      expect(note.plainTextPreview, '');
    });

    test('real Delta note is NOT empty and reports text', () {
      final note = noteWith('[{"insert":"Hello world\\n"}]');
      expect(note.isEmpty, isFalse);
      expect(note.wordCount, 2);
      expect(note.plainTextPreview, 'Hello world');
    });
  });

  group('Note content — Markdown format', () {
    test('empty Markdown "" is empty', () {
      final note = noteWith('');
      expect(note.isEmpty, isTrue);
      expect(note.wordCount, 0);
      expect(note.plainTextPreview, '');
    });

    test('whitespace-only Markdown is empty', () {
      final note = noteWith('   \n\n  \t');
      expect(note.isEmpty, isTrue);
      expect(note.wordCount, 0);
      expect(note.plainTextPreview, '');
    });

    test('syntax/whitespace-only Markdown is empty', () {
      final note = noteWith('#  \n\n- \n> \n---');
      expect(note.isEmpty, isTrue);
      expect(note.wordCount, 0);
    });

    test('real Markdown note is NOT empty and reports text', () {
      final note = noteWith('# Title\n\nSome **text** here.');
      expect(note.isEmpty, isFalse);
      // "Title Some text here." -> 4 words.
      expect(note.wordCount, 4);
      expect(note.plainTextPreview, contains('Title'));
      expect(note.plainTextPreview, contains('text'));
      // Markers must be stripped from the preview.
      expect(note.plainTextPreview, isNot(contains('#')));
      expect(note.plainTextPreview, isNot(contains('*')));
    });

    test('Markdown with links/images keeps visible text', () {
      final note =
          noteWith('See [the docs](https://x.dev) and ![alt](img.png)');
      expect(note.isEmpty, isFalse);
      expect(note.plainTextPreview, contains('the docs'));
      expect(note.plainTextPreview, isNot(contains('https://x.dev')));
    });
  });

  group('Note content — DATA SAFETY (never delete real text)', () {
    test('a real Markdown note is never judged empty', () {
      final note = noteWith('Just a plain markdown line with words.');
      expect(note.isEmpty, isFalse);
    });

    test('a real Delta note is never judged empty', () {
      final note = noteWith('[{"insert":"Important content\\n"}]');
      expect(note.isEmpty, isFalse);
    });

    test('getters never throw on either format', () {
      for (final content in <String>[
        '[]',
        '',
        '# Heading',
        '[{"insert":"x\\n"}]',
        'not json [ but starts weird',
        '- [ ] todo item text',
      ]) {
        final note = noteWith(content);
        expect(() => note.isEmpty, returnsNormally);
        expect(() => note.wordCount, returnsNormally);
        expect(() => note.plainTextPreview, returnsNormally);
      }
    });
  });

  group('Note.createDaily', () {
    test('seeds empty Markdown content and is judged empty', () {
      final note = Note.createDaily(id: 'daily-1', date: DateTime(2026, 3, 4));
      expect(note.content, '');
      expect(note.isEmpty, isTrue);
    });

    test('both legacy "[]" and new "" seeds are treated as empty', () {
      expect(noteWith('[]').isEmpty, isTrue);
      expect(noteWith('').isEmpty, isTrue);
    });
  });
}
