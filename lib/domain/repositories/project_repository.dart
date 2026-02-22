import '../entities/project.dart';
import '../value_objects/sync_status.dart';

/// Port: read/write access to projects.
abstract class ProjectRepository {
  Future<List<Project>> getAll();
  Future<Project?> getById(String id);
  Future<void> save(Project project); // insert or update
  Future<void> delete(String id);

  /// Retrieve projects by sync status.
  Future<List<Project>> getBySyncStatus(SyncStatus status);

  /// Retrieve projects modified since [since].
  Future<List<Project>> getModifiedSince(DateTime since);
}
