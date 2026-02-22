import '../value_objects/sync_result.dart';

/// Port (interface) for the sync engine.
///
/// Handles bidirectional synchronization between local and remote storage.
/// Implementations know about both local DB and remote backend.
abstract class SyncService {
  /// Whether a sync is currently in progress.
  bool get isSyncing;

  /// Push all locally pending changes to remote.
  /// Returns a [SyncResult] with counts of pushed entities.
  Future<SyncResult> pushChanges(String userId, {DateTime? since});

  /// Pull remote changes since [since] and merge into local DB.
  /// Returns a [SyncResult] with counts of pulled entities.
  Future<SyncResult> pullChanges(String userId, {DateTime? since});

  /// Full pull of all remote data (for new device / first login).
  Future<void> fullPull(String userId);

  /// Get the last sync timestamp for a user.
  Future<DateTime?> getLastSyncedAt(String userId);

  /// Set the last sync timestamp for a user.
  Future<void> setLastSyncedAt(String userId, DateTime timestamp);

  /// Returns the userId stored in local sync metadata, if any.
  /// Used to detect account switches.
  Future<String?> getStoredUserId();

  /// Clear all local data (used when switching to a different account).
  Future<void> clearLocalData();
}
