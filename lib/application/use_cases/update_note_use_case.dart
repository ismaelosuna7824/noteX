import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/value_objects/sync_status.dart';

/// Use case: Update an existing note.
///
/// Marks the note as pendingSync and updates the timestamp.
class UpdateNoteUseCase {
  final NoteRepository _repository;

  const UpdateNoteUseCase(this._repository);

  /// Updates the note with the given fields.
  Future<Note?> execute({
    required String noteId,
    String? title,
    String? content,
    String? backgroundImage,
    String? themeId,
    bool? isPinned,
  }) async {
    final existing = await _repository.getById(noteId);
    if (existing == null) return null;

    // Preserve localOnly status for unauthenticated users;
    // only promote to pendingSync if the note was already tracked by sync.
    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.copyWith(
      title: title,
      content: content,
      updatedAt: DateTime.now(),
      syncStatus: newSyncStatus,
      backgroundImage: backgroundImage,
      themeId: themeId,
      isPinned: isPinned,
    );

    await _repository.save(updated);
    return updated;
  }
}
