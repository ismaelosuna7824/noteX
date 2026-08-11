/// The `@query` token being composed at the caret.
class MentionQuery {
  /// Offset of the `@` that opened the token.
  final int start;

  /// Offset just past the query — the caret position that produced it.
  final int end;

  /// Text typed between the `@` and the caret. Empty right after `@`.
  final String query;

  const MentionQuery({
    required this.start,
    required this.end,
    required this.query,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MentionQuery &&
          start == other.start &&
          end == other.end &&
          query == other.query;

  @override
  int get hashCode => Object.hash(start, end, query);

  @override
  String toString() => 'MentionQuery(@$query at $start..$end)';
}

/// The text edit that completes a mention.
class MentionInsertion {
  /// The full replacement text for the field.
  final String text;

  /// Where the caret should land — just past the inserted link.
  final int caret;

  const MentionInsertion({required this.text, required this.caret});
}

/// Authoring grammar for note links: how an `@` typed in the editor becomes a
/// Markdown link to another note.
///
/// Pure domain logic — no Flutter, no widgets, no I/O. This is the write-side
/// counterpart to `NoteLinkParser`, which is the read side. Keeping both pure
/// and in the domain is what lets the whole @mention behaviour be tested
/// without pumping a single widget.
class MentionTrigger {
  const MentionTrigger._();

  /// Longest query we will keep scanning back through. A mention is a short
  /// title fragment; past this the user is writing prose that happens to
  /// contain an `@`.
  static const maxQueryLength = 50;

  /// Detects the mention being composed at [caret] in [text], or null.
  ///
  /// A mention opens on an `@` that starts the text or follows whitespace, so
  /// `user@example.com` never triggers one. The token ends at the caret and
  /// cannot span whitespace — typing a space abandons the mention, which is
  /// also how the user dismisses it without reaching for Escape.
  static MentionQuery? detect({required String text, required int caret}) {
    if (caret < 0 || caret > text.length) return null;

    for (var i = caret - 1; i >= 0 && caret - i <= maxQueryLength + 1; i--) {
      final char = text[i];

      if (char == '@') {
        final precededByBoundary = i == 0 || _isWhitespace(text[i - 1]);
        if (!precededByBoundary) return null;
        return MentionQuery(
          start: i,
          end: caret,
          query: text.substring(i + 1, caret),
        );
      }

      // Whitespace before finding an '@' means there is no open token.
      if (_isWhitespace(char)) return null;
    }

    return null;
  }

  /// Replaces the composing [trigger] with a Markdown link to [noteId].
  ///
  /// Produces an ordinary `[display](notex://<id>)` link — no custom syntax
  /// and no custom attribution, so the preview renderer and the existing
  /// `notex://` tap routing handle it with no extra work, and the link
  /// survives being copied into any other Markdown document.
  static MentionInsertion complete({
    required String text,
    required MentionQuery trigger,
    required String noteId,
    required String displayText,
  }) {
    final link = '[${_sanitizeDisplay(displayText)}](${linkHref(noteId)})';
    final newText =
        text.replaceRange(trigger.start, trigger.end, link);
    return MentionInsertion(
      text: newText,
      caret: trigger.start + link.length,
    );
  }

  /// The href used for a link pointing at [noteId].
  static String linkHref(String noteId) => 'notex://$noteId';

  /// Makes [displayText] safe to sit inside a Markdown link label.
  ///
  /// Brackets would terminate the label early and newlines would break the
  /// link across a paragraph boundary, so both are neutralised. An untitled
  /// note still needs something clickable, hence the fallback.
  static String _sanitizeDisplay(String displayText) {
    final flattened = displayText
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('[', '(')
        .replaceAll(']', ')')
        .trim();
    return flattened.isEmpty ? 'Untitled note' : flattened;
  }

  static bool _isWhitespace(String char) => char.trim().isEmpty;
}
