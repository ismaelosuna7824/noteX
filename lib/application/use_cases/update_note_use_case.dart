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

    final updated = existing.copyWith(
      title: title,
      content: content,
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
      backgroundImage: backgroundImage,
      themeId: themeId,
      isPinned: isPinned,
    );

    await _repository.save(updated);
    return updated;
  }
}
