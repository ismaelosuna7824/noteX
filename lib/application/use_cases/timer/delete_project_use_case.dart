import '../../../domain/repositories/project_repository.dart';
import '../../../domain/repositories/time_entry_repository.dart';
import '../../services/sync_engine.dart';

/// Use case: Soft-delete a timer project and all its time entries, then sync.
class DeleteProjectUseCase {
  final ProjectRepository _projectRepo;
  final TimeEntryRepository _entryRepo;
  final SyncEngine _syncEngine;

  const DeleteProjectUseCase(
      this._projectRepo, this._entryRepo, this._syncEngine);

  Future<void> execute(String projectId) async {
    // Soft-delete all time entries belonging to this project
    final entries = await _entryRepo.getByProjectId(projectId);
    for (final entry in entries) {
      await _entryRepo.save(entry.markDeleted());
    }

    // Soft-delete the project itself
    final project = await _projectRepo.getById(projectId);
    if (project != null) {
      await _projectRepo.save(project.markDeleted());
    }

    await _syncEngine.syncIfAuthenticated();
  }
}
