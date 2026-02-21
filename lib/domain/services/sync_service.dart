import '../entities/note.dart';

/// Port (interface) for the sync engine.
///
/// Handles bidirectional synchronization between local and remote storage.
abstract class SyncService {
  /// Push a local note to the remote server.
  Future<void> pushNote(Note note, String userId);

  /// Pull all notes for a user from the remote server.
  Future<List<Note>> pullNotes(String userId);

  /// Perform a full bidirectional sync.
  /// Returns the list of merged/resolved notes.
  Future<List<Note>> fullSync(List<Note> localNotes, String userId);

  /// Check if sync is currently in progress.
  bool get isSyncing;
}
