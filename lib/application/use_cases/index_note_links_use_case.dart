import '../../domain/repositories/note_link_index.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/services/note_link_parser.dart';

/// Use case: keep the note link index in step with note content.
///
/// The index is derived state, so this use case is the only writer: every path
/// that changes a note body funnels through [execute], and nothing else is
/// allowed to invent edges.
class IndexNoteLinksUseCase {
  final NoteRepository _notes;
  final NoteLinkIndex _index;

  const IndexNoteLinksUseCase(this._notes, this._index);

  /// Re-parse [content] and replace the outgoing edges of [noteId].
  ///
  /// Pass [content] when the caller already has the freshly saved body — the
  /// common case, straight after an auto-save — to avoid a needless read.
  Future<void> execute({required String noteId, String? content}) async {
    final body = content ?? (await _notes.getById(noteId))?.content;
    if (body == null) return;

    await _index.replaceLinksFrom(
      noteId,
      NoteLinkParser.parse(sourceNoteId: noteId, content: body),
    );
  }

  /// Drop every edge touching [noteId], in either direction.
  ///
  /// For permanent deletion only. A trashed note keeps its edges so that
  /// restoring it restores its links too.
  Future<void> forget(String noteId) => _index.removeNote(noteId);

  /// Rebuild the whole index from scratch by re-parsing every note.
  ///
  /// Safe to call at any time: this is what makes the index disposable. Used
  /// for first-run population after the v16 migration, and as the recovery
  /// path if the index is ever suspected of drifting from note content.
  Future<int> rebuildAll() async {
    await _index.clear();

    var edges = 0;
    for (final note in await _notes.getAll()) {
      final links = NoteLinkParser.parse(
        sourceNoteId: note.id,
        content: note.content,
      );
      if (links.isEmpty) continue;
      await _index.replaceLinksFrom(note.id, links);
      edges += links.length;
    }
    return edges;
  }
}
