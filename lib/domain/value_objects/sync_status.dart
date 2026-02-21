/// Represents the synchronization status of a note.
enum SyncStatus {
  /// Note exists only locally (user not authenticated).
  localOnly,

  /// Note has been modified locally and needs to be synced.
  pendingSync,

  /// Note is fully synced with the remote server.
  synced,

  /// Note has a conflict between local and remote versions.
  conflict,
}
