import '../value_objects/sync_status.dart';

/// Core domain entity representing a task.
///
/// Tasks have a title and a scheduled date. Uncompleted tasks
/// accumulate — they carry over to the next day until marked complete.
class Task {
  final String id;
  final String title;
  final DateTime scheduledDate;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String? userId;

  const Task({
    required this.id,
    required this.title,
    required this.scheduledDate,
    this.isCompleted = false,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
    this.deletedAt,
    this.syncStatus = SyncStatus.localOnly,
    this.userId,
  });

  factory Task.create({
    required String id,
    required String title,
    required DateTime scheduledDate,
    String? userId,
  }) {
    final now = DateTime.now();
    return Task(
      id: id,
      title: title,
      scheduledDate: DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
        12,
        0,
        0,
      ),
      isCompleted: false,
      createdAt: now,
      updatedAt: now,
      version: 1,
      syncStatus: SyncStatus.localOnly,
      userId: userId,
    );
  }

  bool get isDeleted => deletedAt != null;

  bool isForDate(DateTime date) {
    return scheduledDate.year == date.year &&
        scheduledDate.month == date.month &&
        scheduledDate.day == date.day;
  }

  Task copyWith({
    String? title,
    DateTime? scheduledDate,
    bool? isCompleted,
    Object? completedAt = const _Unset(),
    DateTime? updatedAt,
    int? version,
    Object? deletedAt = const _Unset(),
    SyncStatus? syncStatus,
    Object? userId = const _Unset(),
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt is _Unset
          ? this.completedAt
          : completedAt as DateTime?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deletedAt: deletedAt is _Unset ? this.deletedAt : deletedAt as DateTime?,
      syncStatus: syncStatus ?? this.syncStatus,
      userId: userId is _Unset ? this.userId : userId as String?,
    );
  }

  Task markCompleted() {
    return copyWith(
      isCompleted: true,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Task markPendingSync() {
    return copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  Task markSynced() => copyWith(syncStatus: SyncStatus.synced);

  Task markDeleted() {
    return copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  Task incrementVersion() => copyWith(version: version + 1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Task && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Task(id: $id, title: $title)';
}

class _Unset {
  const _Unset();
}
