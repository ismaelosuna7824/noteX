/// Resolves internal note links written in a note's Markdown body.
///
/// Pure domain logic: no I/O, no Flutter, no persistence. It is the single
/// source of truth for how a `notex://` href maps to a note id — every surface
/// that can open a link resolves ids through [noteIdFromHref], so a link means
/// the same note wherever it is tapped.
class NoteLinkParser {
  const NoteLinkParser._();

  /// URI scheme identifying a link that points at another note in this app.
  static const internalScheme = 'notex';

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
}
