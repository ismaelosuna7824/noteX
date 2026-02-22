import '../../../domain/repositories/markdown_file_repository.dart';
import '../../services/sync_engine.dart';

/// Use case: Soft-delete a markdown file and trigger sync.
class DeleteMarkdownFileUseCase {
  final MarkdownFileRepository _repository;
  final SyncEngine _syncEngine;

  const DeleteMarkdownFileUseCase(this._repository, this._syncEngine);

  Future<void> execute(String fileId) async {
    final file = await _repository.getById(fileId);
    if (file == null) return;

    // Soft-delete: set deletedAt + pendingSync so sync engine pushes it
    await _repository.save(file.markDeleted());
    await _syncEngine.syncIfAuthenticated();
  }
}
