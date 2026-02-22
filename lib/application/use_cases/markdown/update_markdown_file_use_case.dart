import '../../../domain/entities/markdown_file.dart';
import '../../../domain/repositories/markdown_file_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: Update an existing markdown file.
///
/// Marks the file as pendingSync and updates the timestamp.
class UpdateMarkdownFileUseCase {
  final MarkdownFileRepository _repository;

  const UpdateMarkdownFileUseCase(this._repository);

  Future<MarkdownFile?> execute({
    required String fileId,
    String? title,
    String? content,
  }) async {
    final existing = await _repository.getById(fileId);
    if (existing == null) return null;

    // Preserve localOnly status for unauthenticated users;
    // only promote to pendingSync if the file was already tracked by sync.
    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.copyWith(
      title: title,
      content: content,
      updatedAt: DateTime.now(),
      syncStatus: newSyncStatus,
    );

    await _repository.save(updated);
    return updated;
  }
}
