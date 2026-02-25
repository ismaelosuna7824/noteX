import '../../domain/repositories/note_repository.dart';

/// Use case: Remove notes whose content is empty.
///
/// Runs on app startup and app close to prevent clutter.
/// A note is considered empty when its Quill Delta body has no meaningful
/// text — the title is irrelevant.
///
/// Uses soft-delete (`markDeleted`) so the sync engine propagates the
/// deletion to Supabase on the next sync cycle.
class CleanupEmptyNotesUseCase {
  final NoteRepository _repository;

  const CleanupEmptyNotesUseCase(this._repository);

  /// Soft-deletes **all** empty notes and marks them for sync.
  /// Returns the number of notes removed.
  Future<int> execute() async {
    final allNotes = await _repository.getAll();
    int removed = 0;
    for (final note in allNotes) {
      if (note.isEmpty) {
        await _repository.save(note.markDeleted());
        removed++;
      }
    }
    return removed;
  }
}
