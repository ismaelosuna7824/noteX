import 'package:flutter_test/flutter_test.dart';
import 'package:notex/infrastructure/content/note_content_format.dart';

/// Helper: builds a Delta JSON string from a list of op maps.
String delta(List<Map<String, dynamic>> ops) {
  final buffer = StringBuffer('[');
  for (var i = 0; i < ops.length; i++) {
    if (i > 0) buffer.write(',');
    buffer.write(_encodeOp(ops[i]));
  }
  buffer.write(']');
  return buffer.toString();
}

// Minimal, dependency-free JSON encoder for the op maps used in these tests.
String _encodeOp(Map<String, dynamic> op) {
  final parts = <String>[];
  op.forEach((key, value) {
    parts.add('${_jsonString(key)}:${_encodeValue(value)}');
  });
  return '{${parts.join(',')}}';
}

String _encodeValue(dynamic value) {
  if (value is String) return _jsonString(value);
  if (value is bool || value is num) return '$value';
  if (value is Map) {
    final parts = <String>[];
    value.forEach((k, v) {
      parts.add('${_jsonString('$k')}:${_encodeValue(v)}');
    });
    return '{${parts.join(',')}}';
  }
  throw ArgumentError('Unsupported value: $value');
}

String _jsonString(String s) {
  final escaped = s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n');
  return '"$escaped"';
}

void main() {
  group('deltaJsonToMarkdown', () {
    test('empty document "[]" converts to empty string', () {
      expect(NoteContentFormat.deltaJsonToMarkdown('[]'), '');
    });

    test('empty document "[ ]" (whitespace) converts to empty string', () {
      expect(NoteContentFormat.deltaJsonToMarkdown('[ ]'), '');
    });

    test('single empty paragraph converts to empty string', () {
      final input = delta([
        {'insert': '\n'},
      ]);
      expect(NoteContentFormat.deltaJsonToMarkdown(input), '');
    });

    test('plain text single paragraph', () {
      final input = delta([
        {'insert': 'Hello world\n'},
      ]);
      expect(NoteContentFormat.deltaJsonToMarkdown(input), 'Hello world');
    });

    group('inline formatting', () {
      test('bold', () {
        final input = delta([
          {'insert': 'Hello '},
          {
            'insert': 'world',
            'attributes': {'bold': true},
          },
          {'insert': '\n'},
        ]);
        expect(
          NoteContentFormat.deltaJsonToMarkdown(input),
          'Hello **world**',
        );
      });

      test('italic', () {
        final input = delta([
          {
            'insert': 'world',
            'attributes': {'italic': true},
          },
          {'insert': '\n'},
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), '*world*');
      });

      test('strikethrough', () {
        final input = delta([
          {
            'insert': 'world',
            'attributes': {'strike': true},
          },
          {'insert': '\n'},
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), '~~world~~');
      });

      test('inline code', () {
        final input = delta([
          {
            'insert': 'world',
            'attributes': {'code': true},
          },
          {'insert': '\n'},
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), '`world`');
      });

      test('link', () {
        final input = delta([
          {
            'insert': 'click',
            'attributes': {'link': 'https://example.com'},
          },
          {'insert': '\n'},
        ]);
        expect(
          NoteContentFormat.deltaJsonToMarkdown(input),
          '[click](https://example.com)',
        );
      });

      test('bold + italic combined on one span', () {
        final input = delta([
          {
            'insert': 'world',
            'attributes': {'bold': true, 'italic': true},
          },
          {'insert': '\n'},
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), '***world***');
      });

      test('bold + italic + strikethrough combined on one span', () {
        final input = delta([
          {
            'insert': 'world',
            'attributes': {'bold': true, 'italic': true, 'strike': true},
          },
          {'insert': '\n'},
        ]);
        expect(
          NoteContentFormat.deltaJsonToMarkdown(input),
          '***~~world~~***',
        );
      });

      test('bold link combined on one span', () {
        final input = delta([
          {
            'insert': 'click',
            'attributes': {'bold': true, 'link': 'https://example.com'},
          },
          {'insert': '\n'},
        ]);
        expect(
          NoteContentFormat.deltaJsonToMarkdown(input),
          '**[click](https://example.com)**',
        );
      });
    });

    group('headers', () {
      test('header 1', () {
        final input = delta([
          {'insert': 'Title'},
          {
            'insert': '\n',
            'attributes': {'header': 1},
          },
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), '# Title');
      });

      test('header 2', () {
        final input = delta([
          {'insert': 'Subtitle'},
          {
            'insert': '\n',
            'attributes': {'header': 2},
          },
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), '## Subtitle');
      });

      test('header 3', () {
        final input = delta([
          {'insert': 'Section'},
          {
            'insert': '\n',
            'attributes': {'header': 3},
          },
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), '### Section');
      });
    });

    group('lists', () {
      test('ordered list with multiple items', () {
        final input = delta([
          {'insert': 'First'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {'insert': 'Second'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {'insert': 'Third'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
        ]);
        expect(
          NoteContentFormat.deltaJsonToMarkdown(input),
          '1. First\n2. Second\n3. Third',
        );
      });

      test('bullet list with multiple items', () {
        final input = delta([
          {'insert': 'First'},
          {
            'insert': '\n',
            'attributes': {'list': 'bullet'},
          },
          {'insert': 'Second'},
          {
            'insert': '\n',
            'attributes': {'list': 'bullet'},
          },
        ]);
        expect(
          NoteContentFormat.deltaJsonToMarkdown(input),
          '- First\n- Second',
        );
      });
    });

    test('blockquote', () {
      final input = delta([
        {'insert': 'quoted text'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ]);
      expect(NoteContentFormat.deltaJsonToMarkdown(input), '> quoted text');
    });

    test('code block wraps consecutive lines in a single fence', () {
      final input = delta([
        {'insert': 'const x = 1;'},
        {
          'insert': '\n',
          'attributes': {'code-block': true},
        },
        {'insert': 'const y = 2;'},
        {
          'insert': '\n',
          'attributes': {'code-block': true},
        },
      ]);
      expect(
        NoteContentFormat.deltaJsonToMarkdown(input),
        '```\nconst x = 1;\nconst y = 2;\n```',
      );
    });

    test('multi-paragraph mixed document round-trips to sensible Markdown', () {
      final input = delta([
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': 'Some '},
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': ' text\n'},
        {'insert': 'Item 1'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': 'Item 2'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ]);
      expect(
        NoteContentFormat.deltaJsonToMarkdown(input),
        '# Title\n\nSome **bold** text\n\n- Item 1\n- Item 2',
      );
    });

    group('data safety (SACRED INVARIANT)', () {
      test('unknown inline attribute still emits its text', () {
        final input = delta([
          {
            'insert': 'hello',
            'attributes': {'someWeirdAttr': true},
          },
          {'insert': '\n'},
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), 'hello');
      });

      test('unknown block attribute still emits its text', () {
        final input = delta([
          {'insert': 'hello'},
          {
            'insert': '\n',
            'attributes': {'unknownBlock': 'value'},
          },
        ]);
        expect(NoteContentFormat.deltaJsonToMarkdown(input), 'hello');
      });

      test('image embed does not throw and preserves surrounding text', () {
        final input = delta([
          {'insert': 'before '},
          {
            'insert': {'image': 'http://example.com/y.png'},
          },
          {'insert': ' after\n'},
        ]);
        late String result;
        expect(
          () => result = NoteContentFormat.deltaJsonToMarkdown(input),
          returnsNormally,
        );
        expect(result, contains('before'));
        expect(result, contains('after'));
        expect(result, contains('http://example.com/y.png'));
      });

      test('unknown embed does not throw and preserves surrounding text', () {
        final input = delta([
          {'insert': 'before '},
          {
            'insert': {'mystery': 'thing'},
          },
          {'insert': ' after\n'},
        ]);
        late String result;
        expect(
          () => result = NoteContentFormat.deltaJsonToMarkdown(input),
          returnsNormally,
        );
        expect(result, contains('before'));
        expect(result, contains('after'));
      });

      test('malformed JSON is returned as-is without throwing', () {
        const malformed = '[{"insert": "broken';
        late String result;
        expect(
          () => result = NoteContentFormat.deltaJsonToMarkdown(malformed),
          returnsNormally,
        );
        expect(result, malformed);
      });
    });
  });

  group('isLegacyDelta', () {
    test('empty document "[]" is detected as Delta', () {
      expect(NoteContentFormat.isLegacyDelta('[]'), isTrue);
    });

    test('Delta JSON is detected as Delta', () {
      final input = delta([
        {'insert': 'x\n'},
      ]);
      expect(NoteContentFormat.isLegacyDelta(input), isTrue);
    });

    test('plain markdown string is NOT detected as Delta', () {
      expect(
        NoteContentFormat.isLegacyDelta('# Hi\n\nsome **text**'),
        isFalse,
      );
    });

    test('empty string is NOT detected as Delta', () {
      expect(NoteContentFormat.isLegacyDelta(''), isFalse);
    });

    test('malformed array is NOT detected as Delta', () {
      expect(NoteContentFormat.isLegacyDelta('[{"insert": "broken'), isFalse);
    });

    test('JSON array of non-op objects is NOT detected as Delta', () {
      expect(NoteContentFormat.isLegacyDelta('[{"foo": "bar"}]'), isFalse);
    });

    test('a markdown line that happens to start with "[" is not Delta', () {
      expect(
        NoteContentFormat.isLegacyDelta('[a link](https://example.com)'),
        isFalse,
      );
    });
  });

  group('ensureMarkdown', () {
    test('already-markdown content is returned unchanged', () {
      const markdown = '# Hi\n\nsome **text**';
      expect(NoteContentFormat.ensureMarkdown(markdown), markdown);
    });

    test('empty string is returned unchanged', () {
      expect(NoteContentFormat.ensureMarkdown(''), '');
    });

    test('legacy Delta content is converted to markdown', () {
      final input = delta([
        {'insert': 'Hello '},
        {
          'insert': 'world',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);
      expect(NoteContentFormat.ensureMarkdown(input), 'Hello **world**');
    });

    test('empty Delta "[]" is converted to empty string', () {
      expect(NoteContentFormat.ensureMarkdown('[]'), '');
    });
  });
}
