import '../../domain/repositories/note_repository.dart';

/// Use case: Remove notes whose content is empty.
///
/// Runs on app startup and app close to prevent clutter.
/// A note is considered empty when its Quill Delta body has no meaningful
/// text — the title is irrelevant.
class CleanupEmptyNotesUseCase {
  final NoteRepository _repository;

  const CleanupEmptyNotesUseCase(this._repository);

  /// Deletes **all** empty notes from the database.
  /// Returns the number of notes removed.
  Future<int> execute() async {
    final allNotes = await _repository.getAll();
    int removed = 0;
    for (final note in allNotes) {
      if (note.isEmpty) {
        await _repository.delete(note.id);
        removed++;
      }
    }
    return removed;
  }
}
