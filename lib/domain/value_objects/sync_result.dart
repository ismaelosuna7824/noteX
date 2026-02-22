/// Tracks the outcome of a sync operation.
class SyncResult {
  final int pushed;
  final int pulled;
  final int conflicts;
  final List<String> errors;
  final SyncResultStatus status;

  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.errors = const [],
    this.status = SyncResultStatus.success,
  });

  factory SyncResult.skipped() =>
      const SyncResult(status: SyncResultStatus.skipped);

  factory SyncResult.offline() =>
      const SyncResult(status: SyncResultStatus.offline);

  factory SyncResult.failed(String error) => SyncResult(
        status: SyncResultStatus.failed,
        errors: [error],
      );

  SyncResult merge(SyncResult other) => SyncResult(
        pushed: pushed + other.pushed,
        pulled: pulled + other.pulled,
        conflicts: conflicts + other.conflicts,
        errors: [...errors, ...other.errors],
        status: errors.isEmpty && other.errors.isEmpty
            ? SyncResultStatus.success
            : SyncResultStatus.failed,
      );

  bool get isSuccess => status == SyncResultStatus.success;

  @override
  String toString() =>
      'SyncResult(status: $status, pushed: $pushed, pulled: $pulled, '
      'conflicts: $conflicts, errors: ${errors.length})';
}

enum SyncResultStatus { success, skipped, offline, failed }
