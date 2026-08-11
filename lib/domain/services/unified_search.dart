import '../entities/markdown_file.dart';
import '../entities/note.dart';

/// Which library a hit came from.
enum SearchSource { note, markdownFile }

/// One result of a search across everything the app stores.
class SearchHit {
  /// Id of the note or file, for the caller to open.
  final String id;

  final SearchSource source;

  /// Title as stored, or a placeholder when the item has none.
  final String title;

  /// A short piece of body text around the match, or empty when the query
  /// only matched the title.
  final String snippet;

  /// Used for ordering, and worth showing next to a result.
  final DateTime updatedAt;

  const SearchHit({
    required this.id,
    required this.source,
    required this.title,
    required this.snippet,
    required this.updatedAt,
  });
}

/// Searches notes and Markdown files together.
///
/// Pure domain logic — no I/O, no Flutter. It exists because the app keeps two
/// separate libraries, and a person looking for something they wrote should
/// not have to remember which one they put it in.
class UnifiedSearch {
  const UnifiedSearch._();

  /// Characters of body text shown around a match.
  static const snippetRadius = 40;

  /// Shown when an item has no title of its own.
  static const untitled = 'Untitled';

  /// Runs [query] over [notes] and [files].
  ///
  /// An empty or whitespace-only query matches nothing: a search bar with
  /// nothing typed should not dump the whole library into a dropdown.
  ///
  /// Title matches rank above body-only matches, because someone who names a
  /// note after a thing is more likely to mean that note. Within each band the
  /// most recently edited comes first.
  static List<SearchHit> run({
    required String query,
    required List<Note> notes,
    required List<MarkdownFile> files,
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final titleHits = <SearchHit>[];
    final bodyHits = <SearchHit>[];

    void consider({
      required String id,
      required SearchSource source,
      required String title,
      required String content,
      required DateTime updatedAt,
      required DateTime? deletedAt,
    }) {
      // Trashed items stay out: they are not findable in the app either.
      if (deletedAt != null) return;

      final inTitle = title.toLowerCase().contains(needle);
      final bodyIndex = content.toLowerCase().indexOf(needle);
      if (!inTitle && bodyIndex < 0) return;

      final hit = SearchHit(
        id: id,
        source: source,
        title: title.trim().isEmpty ? untitled : title,
        snippet: bodyIndex < 0 ? '' : snippetAround(content, bodyIndex, needle.length),
        updatedAt: updatedAt,
      );

      (inTitle ? titleHits : bodyHits).add(hit);
    }

    for (final note in notes) {
      consider(
        id: note.id,
        source: SearchSource.note,
        title: note.title,
        content: note.content,
        updatedAt: note.updatedAt,
        deletedAt: note.deletedAt,
      );
    }

    for (final file in files) {
      consider(
        id: file.id,
        source: SearchSource.markdownFile,
        title: file.title,
        content: file.content,
        updatedAt: file.updatedAt,
        deletedAt: file.deletedAt,
      );
    }

    int byRecency(SearchHit a, SearchHit b) =>
        b.updatedAt.compareTo(a.updatedAt);
    titleHits.sort(byRecency);
    bodyHits.sort(byRecency);

    return [...titleHits, ...bodyHits];
  }

  /// A single line of [content] around the match at [index].
  ///
  /// Newlines are flattened so a snippet never breaks the dropdown layout, and
  /// ellipses mark where text was cut so a partial word does not read as the
  /// real beginning of the note.
  static String snippetAround(String content, int index, int matchLength) {
    final flat = content.replaceAll(RegExp(r'\s+'), ' ');

    // Re-locate the match: collapsing whitespace can shift positions.
    final adjusted = flat.toLowerCase().indexOf(
          content.substring(index, index + matchLength).toLowerCase(),
        );
    final at = adjusted < 0 ? 0 : adjusted;

    final start = (at - snippetRadius).clamp(0, flat.length);
    final end = (at + matchLength + snippetRadius).clamp(0, flat.length);

    final buffer = StringBuffer()
      ..write(start > 0 ? '…' : '')
      ..write(flat.substring(start, end).trim())
      ..write(end < flat.length ? '…' : '');

    return buffer.toString();
  }
}
