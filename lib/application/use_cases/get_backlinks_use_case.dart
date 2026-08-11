import '../../domain/entities/note.dart';
import '../../domain/repositories/note_link_index.dart';
import '../../domain/repositories/note_repository.dart';

/// A note that links to the note being viewed, plus the text it used.
class Backlink {
  /// The note containing the link.
  final Note source;

  /// The link text as written in [source] — may differ from the current title
  /// of the linked note, which is exactly why it is worth showing.
  final String displayText;

  const Backlink({required this.source, required this.displayText});
}

/// Use case: list the notes pointing at a given note.
///
/// Backlinks are a *query*, never stored state: this reads the derived index
/// and resolves each edge to its source note.
class GetBacklinksUseCase {
  final NoteRepository _notes;
  final NoteLinkIndex _index;

  const GetBacklinksUseCase(this._notes, this._index);

  /// Notes linking to [noteId], most recently updated first.
  ///
  /// Trashed sources are skipped: a link from the bin is not a live backlink.
  /// Edges whose source note no longer exists are skipped too — they are
  /// harmless leftovers that the next [IndexNoteLinksUseCase.rebuildAll] clears.
  Future<List<Backlink>> execute(String noteId) async {
    final edges = await _index.backlinksTo(noteId);
    if (edges.isEmpty) return const [];

    final backlinks = <Backlink>[];
    for (final edge in edges) {
      final source = await _notes.getById(edge.sourceNoteId);
      if (source == null || source.deletedAt != null) continue;
      backlinks.add(Backlink(source: source, displayText: edge.displayText));
    }

    backlinks.sort((a, b) => b.source.updatedAt.compareTo(a.source.updatedAt));
    return backlinks;
  }
}
