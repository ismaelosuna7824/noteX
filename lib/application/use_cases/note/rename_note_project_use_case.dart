import '../../../domain/entities/note_project.dart';
import '../../../domain/repositories/note_project_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: Rename an existing note project.
class RenameNoteProjectUseCase {
  final NoteProjectRepository _repository;

  const RenameNoteProjectUseCase(this._repository);

  Future<NoteProject?> execute({
    required String projectId,
    required String newName,
  }) async {
    final existing = await _repository.getById(projectId);
    if (existing == null) return null;

    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.copyWith(
      name: newName,
      updatedAt: DateTime.now(),
      syncStatus: newSyncStatus,
    );
    await _repository.save(updated);
    return updated;
  }
}
