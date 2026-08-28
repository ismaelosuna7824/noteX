import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/services/markdown_task_toggle.dart';

void main() {
  group('taskLines — what counts as a task', () {
    test('finds every checkbox in document order', () {
      const source = '- [ ] one\n- [x] two\n- [ ] three';
      expect(MarkdownTaskToggle.taskLines(source), [0, 1, 2]);
    });

    test('counts nested items, at any depth', () {
      const source = '- [ ] one\n  - [x] two\n    - [ ] three';
      expect(MarkdownTaskToggle.taskLines(source), [0, 1, 2]);
    });

    test('accepts every list marker, bullet and ordered alike', () {
      const source = '- [ ] a\n* [ ] b\n+ [ ] c\n1. [ ] d\n2) [ ] e';
      expect(MarkdownTaskToggle.taskLines(source), [0, 1, 2, 3, 4]);
    });

    test('accepts an upper-case X as checked', () {
      expect(MarkdownTaskToggle.isChecked('- [X] shouted', 0), isTrue);
    });

    test('ignores a plain list item', () {
      expect(MarkdownTaskToggle.taskLines('- one\n- two'), isEmpty);
    });

    test('ignores a checkbox with no space after it', () {
      // `- [x]done` is not a task item, and drawing no checkbox for it means a
      // tap must never be able to rewrite it either.
      expect(MarkdownTaskToggle.taskLines('- [x]done'), isEmpty);
    });

    test('ignores a bare bracket pair that is not a list item', () {
      expect(MarkdownTaskToggle.taskLines('[ ] not a list'), isEmpty);
    });
  });

  group('taskLines — fenced code', () {
    test('skips task lines inside a fence', () {
      const source = '- [ ] real\n```\n- [ ] example\n```\n- [ ] also real';
      expect(MarkdownTaskToggle.taskLines(source), [0, 4]);
    });

    test('skips task lines inside a tilde fence', () {
      const source = '- [ ] real\n~~~\n- [ ] example\n~~~\n- [ ] also real';
      expect(MarkdownTaskToggle.taskLines(source), [0, 4]);
    });

    test('a backtick fence is not closed by tildes', () {
      const source = '```\n- [ ] hidden\n~~~\n- [ ] still hidden\n```\n- [ ] real';
      expect(MarkdownTaskToggle.taskLines(source), [5]);
    });

    test('a closing fence must be at least as long as the one that opened', () {
      const source = '````\n- [ ] hidden\n```\n- [ ] still hidden\n````\n- [ ] real';
      expect(MarkdownTaskToggle.taskLines(source), [5]);
    });

    test('a fence carrying an info string still opens a block', () {
      const source = '```dart\n- [ ] example\n```\n- [ ] real';
      expect(MarkdownTaskToggle.taskLines(source), [3]);
    });

    test('an unclosed fence swallows the rest of the document', () {
      const source = '- [ ] real\n```\n- [ ] example';
      expect(MarkdownTaskToggle.taskLines(source), [0]);
    });
  });

  group('toggle', () {
    test('checks an unchecked task', () {
      expect(MarkdownTaskToggle.toggle('- [ ] one', 0), '- [x] one');
    });

    test('unchecks a checked task', () {
      expect(MarkdownTaskToggle.toggle('- [x] one', 0), '- [ ] one');
    });

    test('flips only the task the index addresses', () {
      const source = '- [ ] one\n- [ ] two\n- [ ] three';
      expect(
        MarkdownTaskToggle.toggle(source, 1),
        '- [ ] one\n- [x] two\n- [ ] three',
      );
    });

    test('counts past a fence, so the index still lands on the right line', () {
      const source = '- [ ] one\n```\n- [ ] example\n```\n- [ ] two';
      expect(
        MarkdownTaskToggle.toggle(source, 1),
        '- [ ] one\n```\n- [ ] example\n```\n- [x] two',
      );
    });

    test('keeps the indentation of a nested item', () {
      const source = '- [ ] one\n    - [ ] deep';
      expect(MarkdownTaskToggle.toggle(source, 1), '- [ ] one\n    - [x] deep');
    });

    test('keeps everything after the checkbox exactly as written', () {
      const source = '- [ ]   two spaces and **bold**  ';
      expect(
        MarkdownTaskToggle.toggle(source, 0),
        '- [x]   two spaces and **bold**  ',
      );
    });

    test('leaves the rest of the document untouched', () {
      const source = '# Title\n\n- [ ] one\n\nSome prose.\n';
      expect(
        MarkdownTaskToggle.toggle(source, 0),
        '# Title\n\n- [x] one\n\nSome prose.\n',
      );
    });

    test('preserves CRLF-style trailing returns on other lines', () {
      const source = '- [ ] one\r\n- [ ] two';
      expect(MarkdownTaskToggle.toggle(source, 0), '- [x] one\r\n- [ ] two');
    });

    test('returns null when the index addresses no task', () {
      expect(MarkdownTaskToggle.toggle('- [ ] one', 1), isNull);
      expect(MarkdownTaskToggle.toggle('- [ ] one', -1), isNull);
      expect(MarkdownTaskToggle.toggle('no tasks here', 0), isNull);
    });

    test('a round trip returns the original source', () {
      const source = '- [ ] one\n  - [x] two';
      final once = MarkdownTaskToggle.toggle(source, 1)!;
      expect(MarkdownTaskToggle.toggle(once, 1), source);
    });
  });

  group('isChecked', () {
    test('reads the state of each task', () {
      const source = '- [ ] one\n- [x] two';
      expect(MarkdownTaskToggle.isChecked(source, 0), isFalse);
      expect(MarkdownTaskToggle.isChecked(source, 1), isTrue);
    });

    test('returns null when the index addresses no task', () {
      expect(MarkdownTaskToggle.isChecked('- [ ] one', 5), isNull);
    });
  });
}
