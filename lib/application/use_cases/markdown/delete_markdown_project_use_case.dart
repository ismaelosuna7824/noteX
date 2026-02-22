import '../../../domain/repositories/markdown_file_repository.dart';
import '../../../domain/repositories/markdown_project_repository.dart';
import '../../services/sync_engine.dart';

/// Use case: Soft-delete a markdown project and all its files, then trigger sync.
class DeleteMarkdownProjectUseCase {
  final MarkdownProjectRepository _projectRepo;
  final MarkdownFileRepository _fileRepo;
  final SyncEngine _syncEngine;

  const DeleteMarkdownProjectUseCase(
      this._projectRepo, this._fileRepo, this._syncEngine);

  Future<void> execute(String projectId) async {
    // Soft-delete all files belonging to this project
    final files = await _fileRepo.getByProjectId(projectId);
    for (final file in files) {
      await _fileRepo.save(file.markDeleted());
    }

    // Soft-delete the project itself
    final project = await _projectRepo.getById(projectId);
    if (project != null) {
      await _projectRepo.save(project.markDeleted());
    }

    await _syncEngine.syncIfAuthenticated();
  }
}
