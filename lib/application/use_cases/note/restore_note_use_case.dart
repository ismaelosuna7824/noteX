import '../../../domain/repositories/note_repository.dart';
import '../../../domain/entities/note.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: Restore a soft-deleted note from the trash.
///
/// Clears [deletedAt] and marks the note as [pendingSync] so the
/// restoration propagates to Supabase.
class RestoreNoteUseCase {
  final NoteRepository _repository;

  const RestoreNoteUseCase(this._repository);

  Future<Note?> execute(String noteId) async {
    final note = await _repository.getById(noteId);
    if (note == null) return null;

    final restored = note.copyWith(
      deletedAt: null,
      updatedAt: DateTime.now(),
      syncStatus: note.syncStatus == SyncStatus.localOnly
          ? SyncStatus.localOnly
          : SyncStatus.pendingSync,
    );
    await _repository.save(restored);
    return restored;
  }
}
