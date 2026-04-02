import '../../domain/repositories/note_repository.dart';

/// Use case: Soft-delete a note (moves it to trash).
///
/// Sets [deletedAt] and marks the note as [pendingSync] so the
/// deletion propagates to Supabase. The note remains in the local DB
/// and can be restored from the Trash page.
class DeleteNoteUseCase {
  final NoteRepository _repository;

  const DeleteNoteUseCase(this._repository);

  /// Soft-deletes the note with the given [noteId].
  Future<void> execute(String noteId) async {
    final note = await _repository.getById(noteId);
    if (note == null) return;
    await _repository.save(note.markDeleted());
  }
}
