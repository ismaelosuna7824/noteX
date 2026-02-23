import '../../../domain/repositories/note_repository.dart';
import '../../../domain/repositories/note_project_repository.dart';
import '../../services/sync_engine.dart';

/// Use case: Soft-delete a note project and all its notes, then trigger sync.
class DeleteNoteProjectUseCase {
  final NoteProjectRepository _projectRepo;
  final NoteRepository _noteRepo;
  final SyncEngine _syncEngine;

  const DeleteNoteProjectUseCase(
      this._projectRepo, this._noteRepo, this._syncEngine);

  Future<void> execute(String projectId) async {
    // Soft-delete all notes belonging to this project
    final notes = await _noteRepo.getByProjectId(projectId);
    for (final note in notes) {
      await _noteRepo.save(note.markDeleted());
    }

    // Soft-delete the project itself
    final project = await _projectRepo.getById(projectId);
    if (project != null) {
      await _projectRepo.save(project.markDeleted());
    }

    await _syncEngine.syncIfAuthenticated();
  }
}
