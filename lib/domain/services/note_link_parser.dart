import 'dart:convert';

/// Reads internal note links out of a note's Markdown body.
///
/// Pure domain logic: no I/O, no Flutter, no persistence. It is the single
/// source of truth for how a `notex://` href maps to a note id — every surface
/// that can open a link resolves ids through [noteIdFromHref], so tapping a
/// link and drawing an edge in the graph can never disagree about where it
/// points.
class NoteLinkParser {
  const NoteLinkParser._();

  /// URI scheme identifying a link that points at another note in this app.
  static const internalScheme = 'notex';

  /// Leading slashes of a URI path, stripped when falling back to the path.
  static final _leadingSlashes = RegExp(r'^/+');

  /// Inline Markdown link: `[display](href)`, optionally `[display](href "t")`.
  static final _linkPattern = RegExp(r'\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)');

  /// Opening or closing fence of a fenced code block.
  static final _fencePattern = RegExp(r'^(`{3,}|~{3,})');

  /// A span of inline code — backtick-delimited, single line.
  static final _inlineCodePattern = RegExp(r'`[^`\n]*`');

  /// Every note this body links to.
  ///
  /// Returns bare ids rather than link objects: a graph only needs to know
  /// what connects to what, and a set of ids is the smallest thing that
  /// answers that.
  ///
  /// Links written inside fenced or inline code are ignored. Documenting a
  /// link is not the same as making one — a note explaining the `notex://`
  /// scheme should not sprout edges to every note it uses as an example.
  static Set<String> targetsIn(String content) {
    if (content.isEmpty) return const {};

    final targets = <String>{};
    for (final match in _linkPattern.allMatches(_stripCode(content))) {
      final id = noteIdFromHref(match.group(2));
      if (id != null) targets.add(id);
    }
    return targets;
  }

  /// Removes fenced code blocks and inline code spans from [markdown].
  ///
  /// A closing fence is recognised when a line starts with the same fence
  /// character run that opened the block; an unterminated block swallows the
  /// rest of the document, which is how Markdown renderers treat it too.
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
}
