import '../entities/markdown_file.dart';
import '../value_objects/sync_status.dart';

/// Port (interface) for markdown file persistence operations.
///
/// This is the domain's contract — infrastructure adapters must implement this.
abstract class MarkdownFileRepository {
  /// Retrieve all non-deleted markdown files, ordered by [updatedAt] descending.
  Future<List<MarkdownFile>> getAll();

  /// Retrieve a single markdown file by its [id].
  Future<MarkdownFile?> getById(String id);

  /// Retrieve files filtered by [projectId]. Pass null for root files.
  Future<List<MarkdownFile>> getByProjectId(String? projectId);

  /// Retrieve files filtered by [syncStatus].
  Future<List<MarkdownFile>> getBySyncStatus(SyncStatus status);

  /// Save a markdown file (insert or update).
  Future<void> save(MarkdownFile file);

  /// Delete a markdown file by its [id].
  Future<void> delete(String id);

  /// Delete all markdown files belonging to a [projectId].
  Future<void> deleteByProjectId(String projectId);

  /// Search markdown files by [query] in title or content.
  Future<List<MarkdownFile>> search(String query);

  /// Get the total count of non-deleted markdown files.
  Future<int> count();

  /// Retrieve files modified since [since].
  Future<List<MarkdownFile>> getModifiedSince(DateTime since);
}
