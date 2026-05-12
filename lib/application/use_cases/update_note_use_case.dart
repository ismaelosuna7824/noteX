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
    Object? color = const _Unset(),
    Object? projectId = const _Unset(),
    Object? shareToken = const _Unset(),
    Object? sharedAt = const _Unset(),
    bool? isPinned,
    bool? isEphemeral,
    bool? isLocked,
  }) async {
    final existing = await _repository.getById(noteId);
    if (existing == null) return null;

    // Skip the write when nothing actually changes. Without this, force-saves
    // triggered by side effects (e.g. clicking another note in the list flushes
    // the previously-watched one) would bump `updatedAt` and reorder the list.
    final isNoOp =
        (title == null || title == existing.title) &&
        (content == null || content == existing.content) &&
        (backgroundImage == null || backgroundImage == existing.backgroundImage) &&
        (themeId == null || themeId == existing.themeId) &&
        (color is _Unset || color == existing.color) &&
        (projectId is _Unset || projectId == existing.projectId) &&
        (shareToken is _Unset || shareToken == existing.shareToken) &&
        (sharedAt is _Unset || sharedAt == existing.sharedAt) &&
        (isPinned == null || isPinned == existing.isPinned) &&
        (isEphemeral == null || isEphemeral == existing.isEphemeral) &&
        (isLocked == null || isLocked == existing.isLocked);
    if (isNoOp) return existing;

    // Ephemeral notes always stay localOnly.
    final effectiveEphemeral = isEphemeral ?? existing.isEphemeral;
    final newSyncStatus = effectiveEphemeral
        ? SyncStatus.localOnly
        : (existing.syncStatus == SyncStatus.localOnly
            ? SyncStatus.localOnly
            : SyncStatus.pendingSync);

    final updated = existing.copyWith(
      title: title,
      content: content,
      updatedAt: DateTime.now(),
      syncStatus: newSyncStatus,
      backgroundImage: backgroundImage,
      themeId: themeId,
      color: color is _Unset ? existing.color : color,
      projectId: projectId is _Unset ? existing.projectId : projectId,
      shareToken: shareToken is _Unset ? existing.shareToken : shareToken,
      sharedAt: sharedAt is _Unset ? existing.sharedAt : sharedAt,
      isPinned: isPinned,
      isEphemeral: isEphemeral,
      isLocked: isLocked,
    );

    await _repository.save(updated);
    return updated;
  }
}

// Private sentinel for nullable color parameter.
class _Unset {
  const _Unset();
}
