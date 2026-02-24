import '../value_objects/sync_status.dart';

/// Core domain entity representing a reminder.
///
/// Reminders have a title and a scheduled date. Uncompleted reminders
/// accumulate — they carry over to the next day until marked complete.
class Reminder {
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

  const Reminder({
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

  factory Reminder.create({
    required String id,
    required String title,
    required DateTime scheduledDate,
    String? userId,
  }) {
    final now = DateTime.now();
    return Reminder(
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

  Reminder copyWith({
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
    return Reminder(
      id: id,
      title: title ?? this.title,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt:
          completedAt is _Unset ? this.completedAt : completedAt as DateTime?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deletedAt: deletedAt is _Unset ? this.deletedAt : deletedAt as DateTime?,
      syncStatus: syncStatus ?? this.syncStatus,
      userId: userId is _Unset ? this.userId : userId as String?,
    );
  }

  Reminder markCompleted() {
    return copyWith(
      isCompleted: true,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Reminder markPendingSync() {
    return copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  Reminder markSynced() => copyWith(syncStatus: SyncStatus.synced);

  Reminder markDeleted() {
    return copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  Reminder incrementVersion() => copyWith(version: version + 1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Reminder && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Reminder(id: $id, title: $title)';
}

class _Unset {
  const _Unset();
}
