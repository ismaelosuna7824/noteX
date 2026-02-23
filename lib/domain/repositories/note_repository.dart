import '../entities/note.dart';
import '../value_objects/sync_status.dart';

/// Port (interface) for note persistence operations.
///
/// This is the domain's contract — infrastructure adapters must implement this.
abstract class NoteRepository {
  /// Retrieve all notes, optionally ordered by [createdAt] descending.
  Future<List<Note>> getAll();

  /// Retrieve a single note by its [id].
  Future<Note?> getById(String id);

  /// Retrieve the note for a specific [date], if it exists.
  Future<Note?> getByDate(DateTime date);

  /// Retrieve notes filtered by [syncStatus].
  Future<List<Note>> getBySyncStatus(SyncStatus status);

  /// Save a note (insert or update).
  Future<void> save(Note note);

  /// Delete a note by its [id].
  Future<void> delete(String id);

  /// Search notes by [query] in title or content.
  Future<List<Note>> search(String query);

  /// Retrieve notes belonging to a specific project.
  Future<List<Note>> getByProjectId(String projectId);

  /// Get the total count of notes.
  Future<int> count();

  /// Retrieve notes modified since [since].
  Future<List<Note>> getModifiedSince(DateTime since);
}
