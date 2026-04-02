import '../../domain/repositories/note_repository.dart';

/// Use case: Remove notes whose content is empty.
///
/// Runs on app startup and app close to prevent clutter.
/// A note is considered empty when its Quill Delta body has no meaningful
/// text — the title is irrelevant.
///
/// Uses hard-delete so empty notes are removed completely and don't
/// clutter the Trash page.
class CleanupEmptyNotesUseCase {
  final NoteRepository _repository;

  const CleanupEmptyNotesUseCase(this._repository);

  /// Hard-deletes **all** empty notes.
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
