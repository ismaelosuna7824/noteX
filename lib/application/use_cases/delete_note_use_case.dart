import '../../domain/repositories/note_repository.dart';

/// Use case: Delete a note.
class DeleteNoteUseCase {
  final NoteRepository _repository;

  const DeleteNoteUseCase(this._repository);

  /// Deletes the note with the given [noteId].
  Future<void> execute(String noteId) => _repository.delete(noteId);
}
