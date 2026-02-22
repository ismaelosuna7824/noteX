import '../value_objects/sync_status.dart';

/// A single time-tracked work session.
///
/// When [endTime] is null, the entry is currently running.
class TimeEntry {
  final String id;
  final String description;
  final String? projectId; // null = "No Project"
  final DateTime startTime;
  final DateTime? endTime; // null = currently running
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String? userId;

  const TimeEntry({
    required this.id,
    required this.description,
    required this.startTime,
    required this.updatedAt,
    this.projectId,
    this.endTime,
    this.version = 1,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingSync,
    this.userId,
  });

  /// True when this entry has no end time (the timer is live).
  bool get isRunning => endTime == null;

  /// Whether this entry has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Elapsed duration. If running, measures against [DateTime.now()].
  Duration get elapsed =>
      (endTime ?? DateTime.now()).difference(startTime);

  /// Returns a stopped copy with [endTime] set to now.
  TimeEntry stop() {
    final now = DateTime.now();
    return TimeEntry(
      id: id,
      description: description,
      projectId: projectId,
      startTime: startTime,
      endTime: now,
      updatedAt: now,
      version: version,
      deletedAt: deletedAt,
      syncStatus: SyncStatus.pendingSync,
      userId: userId,
    );
  }

  TimeEntry copyWith({
    String? description,
    Object? projectId = const _Unset(),
    DateTime? startTime,
    Object? endTime = const _Unset(),
    DateTime? updatedAt,
    int? version,
    Object? deletedAt = const _Unset(),
    SyncStatus? syncStatus,
    Object? userId = const _Unset(),
  }) {
    return TimeEntry(
      id: id,
      description: description ?? this.description,
      projectId: projectId is _Unset ? this.projectId : projectId as String?,
      startTime: startTime ?? this.startTime,
      endTime: endTime is _Unset ? this.endTime : endTime as DateTime?,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deletedAt: deletedAt is _Unset ? this.deletedAt : deletedAt as DateTime?,
      syncStatus: syncStatus ?? this.syncStatus,
      userId: userId is _Unset ? this.userId : userId as String?,
    );
  }

  TimeEntry markPendingSync() {
    return copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  TimeEntry markSynced() {
    return copyWith(syncStatus: SyncStatus.synced);
  }

  TimeEntry markDeleted() {
    return copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  TimeEntry incrementVersion() {
    return copyWith(version: version + 1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TimeEntry && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TimeEntry(id: $id, desc: $description, running: $isRunning)';
}

// Private sentinel for nullable copyWith fields.
class _Unset {
  const _Unset();
}
