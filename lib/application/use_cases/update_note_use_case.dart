import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/value_objects/sync_status.dart';
import 'index_note_links_use_case.dart';

/// Use case: Update an existing note.
///
/// Marks the note as pendingSync and updates the timestamp, and keeps the
/// note link index in step with the body. Every surface that saves a note —
/// the editor's auto-save, the tiling panels, title generation — funnels
/// through here, which is what makes this the one place indexing has to live.
class UpdateNoteUseCase {
  final NoteRepository _repository;
  final IndexNoteLinksUseCase _indexLinks;

  const UpdateNoteUseCase(this._repository, this._indexLinks);

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

    // Only a body change can move links, so a title edit or a pin toggle
    // skips the re-parse entirely.
    if (content != null && content != existing.content) {
      await _reindexLinks(noteId, content);
    }

    return updated;
  }

  /// Re-parses the note's links, never at the cost of the save itself.
  ///
  /// A failure here is swallowed on purpose. The note is already persisted,
  /// and the index is derived state that
  /// [IndexNoteLinksUseCase.rebuildAll] can reproduce from note bodies at any
  /// time — so a stale index is a recoverable inconvenience, while turning it
  /// into a thrown error would report a successful save as a failed one.
  Future<void> _reindexLinks(String noteId, String content) async {
    try {
      await _indexLinks.execute(noteId: noteId, content: content);
    } catch (_) {
      // Intentionally ignored — see above.
    }
  }
}

// Private sentinel for nullable color parameter.
class _Unset {
  const _Unset();
}
