/// The lifecycle state of a [Task].
///
/// Persisted as `.name` (never an index) — same convention as [SyncStatus].
enum TaskStatus {
  /// Not yet started.
  todo,

  /// In progress.
  doing,

  /// Stalled on something outside the user's control. `blockedReason`
  /// carries the user-authored explanation.
  blocked,

  /// Finished.
  done,
}
