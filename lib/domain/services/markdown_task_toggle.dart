/// Flipping a task checkbox in Markdown source, by the position the reader
/// tapped rather than by the text they tapped on.
///
/// The rendered preview has no idea which line of source it came from — the
/// parser hands the renderer an element tree with no positions in it. What the
/// renderer *does* know is ordinal: this is the nth checkbox on the page. So
/// the contract here is ordinal too, and it holds because the parser walks the
/// document in source order: the nth checkbox drawn is the nth task line
/// written.
///
/// Matching on the item's text instead would be the obvious alternative and it
/// is worse. Two items may read the same, and an item may be edited between the
/// render and the tap.
abstract final class MarkdownTaskToggle {
  /// `- [ ] `, `* [x] `, `1. [ ] ` — a list marker, then a checkbox, then at
  /// least one space. The trailing space is required by the spec and by this
  /// pattern: `- [x]note` is not a task item, and treating it as one would let
  /// a tap rewrite a line the reader never saw a checkbox on.
  static final RegExp _task = RegExp(
    r'^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\]\s)',
  );

  /// Opening or closing fence of a code block, with any indent and any info
  /// string. Both fence characters, three or more of them, as CommonMark says.
  static final RegExp _fence = RegExp(r'^\s*(`{3,}|~{3,})');

  /// Every task line in [source], in document order, as line indices.
  ///
  /// Lines inside fenced code are skipped. A fenced block is documentation
  /// *about* Markdown as often as not, and `- [ ] example` inside one is text
  /// the renderer never draws a checkbox for — counting it would shift every
  /// index after it and make taps rewrite the wrong line.
  static List<int> taskLines(String source) {
    final List<String> lines = source.split('\n');
    final List<int> found = <int>[];

    // The fence character and length that opened the current block, so a ``` in
    // a ~~~ block (or a shorter run) does not close it early.
    String? openChar;
    int openLength = 0;

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final RegExpMatch? fence = _fence.firstMatch(line);

      if (fence != null) {
        final String run = fence.group(1)!;
        final String char = run[0];
        if (openChar == null) {
          openChar = char;
          openLength = run.length;
          continue;
        }
        // A closing fence must use the same character and be at least as long
        // as the one that opened the block.
        if (char == openChar && run.length >= openLength) {
          openChar = null;
          openLength = 0;
        }
        continue;
      }

      if (openChar != null) continue;
      if (_task.hasMatch(line)) found.add(i);
    }

    return found;
  }

  /// Whether the task at [index] is checked, or null when there is no such
  /// task. Lets a caller read the state it is about to change without parsing
  /// the source a second way.
  static bool? isChecked(String source, int index) {
    final List<int> lines = taskLines(source);
    if (index < 0 || index >= lines.length) return null;
    final String line = source.split('\n')[lines[index]];
    return _task.firstMatch(line)!.group(2)!.toLowerCase() == 'x';
  }

  /// [source] with the checkbox of the task at [index] flipped.
  ///
  /// Returns null when [index] addresses no task, which is the honest answer
  /// for a tap that arrived after the text changed underneath it. Callers
  /// should leave the document alone rather than guess at a nearby line.
  static String? toggle(String source, int index) {
    final List<int> lines = taskLines(source);
    if (index < 0 || index >= lines.length) return null;

    final List<String> split = source.split('\n');
    final int target = lines[index];
    final RegExpMatch match = _task.firstMatch(split[target])!;

    final bool checked = match.group(2)!.toLowerCase() == 'x';
    final String head = match.group(1)!;
    final String tail = match.group(3)!;
    // Only the three matched groups are rebuilt; everything after them is the
    // author's own text and is carried over untouched, whitespace included.
    split[target] =
        '$head${checked ? ' ' : 'x'}$tail${split[target].substring(match.end)}';

    return split.join('\n');
  }
}
