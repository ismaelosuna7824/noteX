import 'dart:convert';

import '../value_objects/note_link.dart';

/// Extracts internal note-to-note links out of a note's Markdown body.
///
/// This is pure domain logic: no I/O, no Flutter, no persistence. It is the
/// single source of truth for how a `notex://` href maps to a note id — both
/// the editor's tap handler and the link index resolve ids through
/// [noteIdFromHref] so navigation and backlinks can never disagree.
class NoteLinkParser {
  const NoteLinkParser._();

  /// URI scheme identifying a link that points at another note in this app.
  static const internalScheme = 'notex';

  /// Inline Markdown link: `[display](href)`, optionally `[display](href "t")`.
  static final _linkPattern = RegExp(r'\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)');

  /// Opening or closing fence of a fenced code block.
  static final _fencePattern = RegExp(r'^(`{3,}|~{3,})');

  /// A span of inline code — backtick-delimited, single line.
  static final _inlineCodePattern = RegExp(r'`[^`\n]*`');

  /// Leading slashes of a URI path, stripped when falling back to the path.
  static final _leadingSlashes = RegExp(r'^/+');

  /// Resolves the note id addressed by [href], or null if [href] is not an
  /// internal note link.
  ///
  /// The id is the URI *host*, falling back to the path for hrefs parsed
  /// without an authority component (`notex:/id` or `notex:id`). Note that
  /// `Uri` lower-cases hosts, so ids must be compared case-insensitively —
  /// the app's uuid v4 ids are already lower-case hex.
  static String? noteIdFromHref(String? href) {
    if (href == null || href.isEmpty) return null;
    final uri = Uri.tryParse(href);
    if (uri == null || uri.scheme != internalScheme) return null;
    final id = uri.host.isNotEmpty
        ? uri.host
        : uri.path.replaceFirst(_leadingSlashes, '');
    return id.isEmpty ? null : id;
  }

  /// Parses every internal link in [content], authored by [sourceNoteId].
  ///
  /// Guarantees, all covered by tests:
  /// * links inside fenced or inline code are ignored — documenting a link is
  ///   not the same as making one;
  /// * a note never links to itself, so it can't appear in its own backlinks;
  /// * repeated links to the same target collapse to one entry, keeping the
  ///   first display text. The index is keyed by (source, target), so a note
  ///   referencing another five times is still one edge in the graph.
  static List<NoteLink> parse({
    required String sourceNoteId,
    required String content,
  }) {
    if (content.isEmpty) return const [];

    final seenTargets = <String>{};
    final links = <NoteLink>[];

    for (final match in _linkPattern.allMatches(_stripCode(content))) {
      final targetNoteId = noteIdFromHref(match.group(2));
      if (targetNoteId == null) continue;
      if (targetNoteId == sourceNoteId) continue;
      if (!seenTargets.add(targetNoteId)) continue;

      links.add(NoteLink(
        sourceNoteId: sourceNoteId,
        targetNoteId: targetNoteId,
        displayText: match.group(1)?.trim() ?? '',
      ));
    }

    return links;
  }

  /// Removes fenced code blocks and inline code spans from [markdown].
  ///
  /// A closing fence is recognised when a line starts with the same fence
  /// character run that opened the block; an unterminated block swallows the
  /// rest of the document, which matches how Markdown renderers treat it.
  static String _stripCode(String markdown) {
    final buffer = StringBuffer();
    String? openFence;

    for (final line in const LineSplitter().convert(markdown)) {
      final trimmed = line.trimLeft();

      if (openFence == null) {
        final fence = _fencePattern.firstMatch(trimmed)?.group(1);
        if (fence != null) {
          openFence = fence;
          continue;
        }
        buffer.writeln(line);
      } else if (trimmed.startsWith(openFence)) {
        openFence = null;
      }
    }

    return buffer.toString().replaceAll(_inlineCodePattern, ' ');
  }
}
