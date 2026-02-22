import '../entities/markdown_project.dart';
import '../value_objects/sync_status.dart';

/// Port (interface) for markdown project persistence operations.
abstract class MarkdownProjectRepository {
  /// Retrieve all non-deleted markdown projects, ordered by name.
  Future<List<MarkdownProject>> getAll();

  /// Retrieve a single markdown project by its [id].
  Future<MarkdownProject?> getById(String id);

  /// Retrieve projects filtered by [syncStatus].
  Future<List<MarkdownProject>> getBySyncStatus(SyncStatus status);

  /// Save a markdown project (insert or update).
  Future<void> save(MarkdownProject project);

  /// Delete a markdown project by its [id].
  Future<void> delete(String id);

  /// Retrieve projects modified since [since].
  Future<List<MarkdownProject>> getModifiedSince(DateTime since);
}
