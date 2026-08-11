import '../../../domain/repositories/note_repository.dart';

/// Use case: Permanently delete a note from the database.
///
/// This is a hard delete — the note is removed from the local DB entirely.
/// Should only be used from the Trash page for notes already soft-deleted.
class PermanentDeleteNoteUseCase {
  final NoteRepository _repository;

  const PermanentDeleteNoteUseCase(this._repository);

  Future<void> execute(String noteId) => _repository.delete(noteId);
}
