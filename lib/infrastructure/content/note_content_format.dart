import 'dart:convert';

/// Converts stored note content between the legacy Quill Delta JSON format and
/// Markdown.
///
/// Notes were historically persisted as a Quill Delta JSON string in
/// `Note.content` (empty content is the literal `'[]'`). The editor now works
/// with Markdown, so legacy notes are converted on read.
///
/// SACRED INVARIANT — data safety: this converter NEVER throws and NEVER drops
/// user text. Unknown inline attributes degrade to plain text, unknown block
/// attributes degrade to a plain paragraph, and non-string embeds are skipped
/// gracefully (images are preserved as Markdown image syntax when a URL is
/// present). Malformed input is returned unchanged rather than crashing.
///
/// Parsing uses `dart:convert` (the standard JSON parser) rather than
/// flutter_quill's `Delta.fromJson`. This is deliberate: `Delta.fromJson`
/// asserts on op length and throws on ops that are not insert/delete/retain,
/// which would violate the never-throw invariant. Delta→Markdown conversion
/// logic has to be written by hand regardless (flutter_quill does not produce
/// Markdown), so decoding the document with the JSON parser and walking the
/// resulting op list is both simpler and strictly safer.
class NoteContentFormat {
  const NoteContentFormat._();

  /// Returns `true` when [content] is legacy Quill Delta JSON, `false` when it
  /// should be treated as Markdown.
  ///
  /// Delta content is a JSON array of insert operations (including the empty
  /// document `'[]'`). Anything that is not a decodable JSON array of insert
  /// ops — including the empty string and ordinary Markdown — is Markdown.
  static bool isLegacyDelta(String content) {
    return _tryDecodeOps(content) != null;
  }

  /// Returns [content] unchanged when it is already Markdown, otherwise
  /// converts it from legacy Delta JSON to Markdown.
  static String ensureMarkdown(String content) {
    final ops = _tryDecodeOps(content);
    if (ops == null) return content;
    return _safeConvert(ops, content);
  }

  /// Converts a Quill Delta JSON string to Markdown.
  ///
  /// Never throws: input that is not a valid Delta array is returned unchanged.
  static String deltaJsonToMarkdown(String deltaJson) {
    final ops = _tryDecodeOps(deltaJson);
    if (ops == null) return deltaJson;
    return _safeConvert(ops, deltaJson);
  }

  // --- internals ----------------------------------------------------------

  /// Attempts to decode [content] as a Delta document (a JSON array whose every
  /// element is an insert op). Returns the list of op maps on success (an empty
  /// list for the empty document `'[]'`), or `null` when [content] is not a
  /// Delta and should be treated as Markdown.
  static List<Map<String, dynamic>>? _tryDecodeOps(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('[')) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;

    final ops = <Map<String, dynamic>>[];
    for (final element in decoded) {
      if (element is! Map) return null;
      if (!element.containsKey('insert')) return null;
      ops.add(Map<String, dynamic>.from(element));
    }
    return ops;
  }

  /// Runs [_convert] but guards against any unexpected error so a conversion
  /// bug can never lose the original [original] content.
  static String _safeConvert(List<Map<String, dynamic>> ops, String original) {
    try {
      return _convert(ops);
    } catch (_) {
      return original;
    }
  }

  static String _convert(List<Map<String, dynamic>> ops) {
    final blocks = <_Block>[];
    final line = StringBuffer();

    void flushLine(Map<String, dynamic>? blockAttrs) {
      blocks.add(_renderBlock(line.toString(), blockAttrs));
      line.clear();
    }

    for (final op in ops) {
      final insert = op['insert'];
      final attrs = op['attributes'];
      final attributes = attrs is Map ? Map<String, dynamic>.from(attrs) : null;

      if (insert is String) {
        // Block-level attributes in Delta ride on the op that inserts the
        // trailing newline. Split on '\n': text before each newline is inline
        // content for the current line; each newline flushes the line and its
        // block attributes come from THIS op.
        final segments = insert.split('\n');
        for (var i = 0; i < segments.length; i++) {
          final segment = segments[i];
          if (segment.isNotEmpty) {
            line.write(_applyInline(segment, attributes));
          }
          final followedByNewline = i < segments.length - 1;
          if (followedByNewline) {
            flushLine(attributes);
          }
        }
      } else if (insert is Map) {
        // Embed (image, video, ...). Preserve what we can; never throw.
        final embed = _renderEmbed(Map<String, dynamic>.from(insert));
        if (embed != null) {
          line.write(embed);
        }
      }
      // Any other insert payload type is skipped gracefully.
    }

    // Trailing inline content with no closing newline.
    if (line.isNotEmpty) {
      flushLine(null);
    }

    return _serialize(blocks);
  }

  /// Applies supported inline attributes to [text]. Unknown attributes are
  /// ignored (the text is still emitted). Wrapping order runs from innermost to
  /// outermost: code, link, strikethrough, italic, bold.
  static String _applyInline(String text, Map<String, dynamic>? attributes) {
    if (attributes == null || attributes.isEmpty) return text;
    var out = text;
    if (attributes['code'] == true) out = '`$out`';
    final link = attributes['link'];
    if (link is String && link.isNotEmpty) out = '[$out]($link)';
    if (attributes['strike'] == true) out = '~~$out~~';
    if (attributes['italic'] == true) out = '*$out*';
    if (attributes['bold'] == true) out = '**$out**';
    return out;
  }

  /// Renders a non-string embed. Images and videos with a URL become Markdown
  /// image syntax; anything else returns `null` (skipped).
  static String? _renderEmbed(Map<String, dynamic> embed) {
    final source = embed['image'] ?? embed['video'];
    if (source is String && source.isNotEmpty) {
      return '![]($source)';
    }
    return null;
  }

  /// Classifies one flushed line into a [_Block] using its block attributes.
  static _Block _renderBlock(String text, Map<String, dynamic>? attributes) {
    if (attributes == null || attributes.isEmpty) {
      return _Block(_BlockKind.paragraph, text);
    }

    final codeBlock = attributes['code-block'];
    if (codeBlock != null && codeBlock != false) {
      final language = codeBlock is String ? codeBlock : '';
      return _Block(_BlockKind.code, text, codeLanguage: language);
    }

    final header = attributes['header'];
    if (header is num) {
      final level = header.toInt().clamp(1, 6);
      return _Block(_BlockKind.header, '${'#' * level} $text');
    }

    if (attributes['blockquote'] == true) {
      return _Block(_BlockKind.quote, '> $text');
    }

    final list = attributes['list'];
    if (list == 'ordered') {
      // The numeral is assigned during serialization so runs number correctly.
      return _Block(_BlockKind.orderedItem, text);
    }
    if (list == 'bullet') {
      return _Block(_BlockKind.bulletItem, '- $text');
    }
    if (list == 'checked') {
      return _Block(_BlockKind.bulletItem, '- [x] $text');
    }
    if (list == 'unchecked') {
      return _Block(_BlockKind.bulletItem, '- [ ] $text');
    }

    // Unknown/unsupported block attribute: degrade to a plain paragraph so the
    // text is never lost.
    return _Block(_BlockKind.paragraph, text);
  }

  /// Joins classified blocks into a Markdown document. Consecutive list items
  /// of the same kind stay tight (single newline); consecutive code lines are
  /// merged into one fenced block; every other adjacent pair is separated by a
  /// blank line.
  static String _serialize(List<_Block> blocks) {
    final units = <_Unit>[];
    var orderedCounter = 0;

    var i = 0;
    while (i < blocks.length) {
      final block = blocks[i];
      switch (block.kind) {
        case _BlockKind.code:
          orderedCounter = 0;
          final buffer = StringBuffer('```');
          final language = block.codeLanguage ?? '';
          if (language.isNotEmpty) buffer.write(language);
          buffer.write('\n');
          var j = i;
          while (j < blocks.length && blocks[j].kind == _BlockKind.code) {
            buffer.write(blocks[j].content);
            buffer.write('\n');
            j++;
          }
          buffer.write('```');
          units.add(_Unit(_BlockKind.code, buffer.toString()));
          i = j;
        case _BlockKind.orderedItem:
          orderedCounter += 1;
          units.add(
            _Unit(_BlockKind.orderedItem, '$orderedCounter. ${block.content}'),
          );
          i++;
        default:
          orderedCounter = 0;
          units.add(_Unit(block.kind, block.content));
          i++;
      }
    }

    final output = StringBuffer();
    for (var k = 0; k < units.length; k++) {
      if (k > 0) {
        output.write(_tight(units[k - 1].kind, units[k].kind) ? '\n' : '\n\n');
      }
      output.write(units[k].content);
    }
    return output.toString();
  }

  /// Whether two adjacent units should be joined with a single newline (tight)
  /// rather than a blank-line separator.
  static bool _tight(_BlockKind previous, _BlockKind current) {
    return (previous == _BlockKind.orderedItem &&
            current == _BlockKind.orderedItem) ||
        (previous == _BlockKind.bulletItem &&
            current == _BlockKind.bulletItem);
  }
}

enum _BlockKind { paragraph, header, quote, orderedItem, bulletItem, code }

/// One flushed line, classified by its block attributes.
class _Block {
  _Block(this.kind, this.content, {this.codeLanguage});

  final _BlockKind kind;
  final String content;
  final String? codeLanguage;
}

/// A serialized output unit (may span multiple lines, e.g. a fenced block).
class _Unit {
  _Unit(this.kind, this.content);

  final _BlockKind kind;
  final String content;
}
