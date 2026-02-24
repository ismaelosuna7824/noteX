import '../../domain/repositories/note_repository.dart';
import '../../domain/value_objects/sync_status.dart';

/// Use case: Remove empty notes that were never modified by the user.
///
/// A note is considered empty when it has no meaningful content
/// (empty Quill Delta or whitespace-only) AND a default date-based title.
/// Only notes with [SyncStatus.localOnly] are candidates — once a note has
/// been synced to the backend we never auto-delete it.
class CleanupEmptyNotesUseCase {
  final NoteRepository _repository;

  const CleanupEmptyNotesUseCase(this._repository);

  /// Deletes **all** empty, local-only notes from the database.
  /// Returns the number of notes removed.
  Future<int> execute() async {
    final allNotes = await _repository.getAll();
    int removed = 0;
    for (final note in allNotes) {
      if (note.isEmpty && note.syncStatus == SyncStatus.localOnly) {
        await _repository.delete(note.id);
        removed++;
      }
    }
    return removed;
  }

  /// Checks a single note and deletes it if empty + local-only.
  /// Returns `true` when the note was deleted.
  Future<bool> executeForNote(String noteId) async {
    final note = await _repository.getById(noteId);
    if (note == null) return false;
    if (note.isEmpty && note.syncStatus == SyncStatus.localOnly) {
      await _repository.delete(noteId);
      return true;
    }
    return false;
  }
}
