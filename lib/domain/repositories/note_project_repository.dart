import '../entities/note_project.dart';
import '../value_objects/sync_status.dart';

/// Port (interface) for note project persistence operations.
abstract class NoteProjectRepository {
  /// Retrieve all non-deleted note projects, ordered by name.
  Future<List<NoteProject>> getAll();

  /// Retrieve a single note project by its [id].
  Future<NoteProject?> getById(String id);

  /// Retrieve projects filtered by [syncStatus].
  Future<List<NoteProject>> getBySyncStatus(SyncStatus status);

  /// Save a note project (insert or update).
  Future<void> save(NoteProject project);

  /// Delete a note project by its [id].
  Future<void> delete(String id);

  /// Retrieve projects modified since [since].
  Future<List<NoteProject>> getModifiedSince(DateTime since);
}
