import '../../../domain/entities/note_project.dart';
import '../../../domain/repositories/note_repository.dart';
import '../../../domain/repositories/note_project_repository.dart';
import '../../services/sync_engine.dart';

/// Use case: Soft-delete a note project, all its descendant projects,
/// and every note inside any of them, then trigger sync.
class DeleteNoteProjectUseCase {
  final NoteProjectRepository _projectRepo;
  final NoteRepository _noteRepo;
  final SyncEngine _syncEngine;

  const DeleteNoteProjectUseCase(
      this._projectRepo, this._noteRepo, this._syncEngine);

  Future<void> execute(String projectId) async {
    final all = await _projectRepo.getAll();
    final toDelete = _collectDescendants(all, projectId);

    for (final id in toDelete) {
      final notes = await _noteRepo.getByProjectId(id);
      for (final note in notes) {
        await _noteRepo.save(note.markDeleted());
      }
    }

    for (final id in toDelete) {
      final project = await _projectRepo.getById(id);
      if (project != null) {
        await _projectRepo.save(project.markDeleted());
      }
    }

    await _syncEngine.syncIfAuthenticated();
  }

  /// BFS over [all] collecting [rootId] and every descendant id.
  Set<String> _collectDescendants(List<NoteProject> all, String rootId) {
    final result = <String>{rootId};
    final queue = <String>[rootId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final p in all) {
        if (p.parentId == current && result.add(p.id)) {
          queue.add(p.id);
        }
      }
    }
    return result;
  }
}
