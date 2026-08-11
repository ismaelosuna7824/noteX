import '../../../domain/repositories/note_repository.dart';
import '../index_note_links_use_case.dart';

/// Use case: Permanently delete a note from the database.
///
/// This is a hard delete — the note is removed from the local DB entirely.
/// Should only be used from the Trash page for notes already soft-deleted.
class PermanentDeleteNoteUseCase {
  final NoteRepository _repository;
  final IndexNoteLinksUseCase _indexLinks;

  const PermanentDeleteNoteUseCase(this._repository, this._indexLinks);

  /// Deletes the note and drops every link edge touching it.
  ///
  /// Edges are forgotten in both directions: the ones this note authored, and
  /// the ones pointing at it. Only a permanent delete does this — a note in the
  /// trash keeps its edges so that restoring it restores its links with it.
  Future<void> execute(String noteId) async {
    await _repository.delete(noteId);
    await _indexLinks.forget(noteId);
  }
}
