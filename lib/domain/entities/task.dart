import '../value_objects/sync_status.dart';
import '../value_objects/task_status.dart';

/// Core domain entity representing a task.
///
/// Tasks have a title and a scheduled date. Uncompleted tasks
/// accumulate — they carry over to the next day until marked complete.
///
/// `status` is the single source of truth for a task's lifecycle state —
/// see design D3. There is no independent `isCompleted` boolean: [isDone]
/// is derived, so it cannot drift from [status].
class Task {
  final String id;
  final String title;
  final DateTime scheduledDate;
  final TaskStatus status;
  final DateTime? statusChangedAt;

  /// Local only — never serialized to Supabase. True whenever this task's
  /// status was set by a transition that has not yet been pushed; the push
  /// payload includes the status quartet only while this is true (D10 R1).
  final bool statusPendingPush;

  final DateTime? completedAt;
  final String description;

  /// User-authored explanation for a `blocked` status. Retained across
  /// transitions — only [Task.transitionTo] (when explicitly passed) or a
  /// deliberate edit may clear it. See design D3.
  final String? blockedReason;

  /// Optional link to a note. No foreign key — see design D9.
  final String? noteId;
  final String? externalProvider;
  final String? externalId;
  final String? externalUrl;
  final String? externalCachedTitle;
  final DateTime? externalLastSyncedAt;

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
    this.status = TaskStatus.todo,
    this.statusChangedAt,
    this.statusPendingPush = false,
    this.completedAt,
    this.description = '',
    this.blockedReason,
    this.noteId,
    this.externalProvider,
    this.externalId,
    this.externalUrl,
    this.externalCachedTitle,
    this.externalLastSyncedAt,
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
      status: TaskStatus.todo,
      // The first push of any task always carries its status (D10).
      statusPendingPush: true,
      createdAt: now,
      updatedAt: now,
      version: 1,
      syncStatus: SyncStatus.localOnly,
      userId: userId,
    );
  }

  bool get isDeleted => deletedAt != null;

  /// True iff [status] is [TaskStatus.done]. Derived, never stored
  /// independently — see the class doc.
  bool get isDone => status == TaskStatus.done;

  bool isForDate(DateTime date) {
    return scheduledDate.year == date.year &&
        scheduledDate.month == date.month &&
        scheduledDate.day == date.day;
  }

  Task copyWith({
    String? title,
    DateTime? scheduledDate,
    TaskStatus? status,
    Object? statusChangedAt = const _Unset(),
    bool? statusPendingPush,
    Object? completedAt = const _Unset(),
    String? description,
    Object? blockedReason = const _Unset(),
    Object? noteId = const _Unset(),
    Object? externalProvider = const _Unset(),
    Object? externalId = const _Unset(),
    Object? externalUrl = const _Unset(),
    Object? externalCachedTitle = const _Unset(),
    Object? externalLastSyncedAt = const _Unset(),
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
      status: status ?? this.status,
      statusChangedAt: statusChangedAt is _Unset
          ? this.statusChangedAt
          : statusChangedAt as DateTime?,
      statusPendingPush: statusPendingPush ?? this.statusPendingPush,
      completedAt:
          completedAt is _Unset ? this.completedAt : completedAt as DateTime?,
      description: description ?? this.description,
      blockedReason: blockedReason is _Unset
          ? this.blockedReason
          : blockedReason as String?,
      noteId: noteId is _Unset ? this.noteId : noteId as String?,
      externalProvider: externalProvider is _Unset
          ? this.externalProvider
          : externalProvider as String?,
      externalId:
          externalId is _Unset ? this.externalId : externalId as String?,
      externalUrl:
          externalUrl is _Unset ? this.externalUrl : externalUrl as String?,
      externalCachedTitle: externalCachedTitle is _Unset
          ? this.externalCachedTitle
          : externalCachedTitle as String?,
      externalLastSyncedAt: externalLastSyncedAt is _Unset
          ? this.externalLastSyncedAt
          : externalLastSyncedAt as DateTime?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deletedAt: deletedAt is _Unset ? this.deletedAt : deletedAt as DateTime?,
      syncStatus: syncStatus ?? this.syncStatus,
      userId: userId is _Unset ? this.userId : userId as String?,
    );
  }

  /// Moves this task to [next].
  ///
  /// A transition resets machine-derived metadata — [statusChangedAt],
  /// [statusPendingPush] and [updatedAt] are set on every call, and
  /// [completedAt] is set to now iff [next] is `done`, else cleared.
  ///
  /// A transition never destroys text a human typed: [blockedReason] is
  /// retained unless explicitly passed — omit to preserve, pass a value to
  /// set it, pass `null` to clear it. Only a deliberate user edit passes
  /// anything here (see design D3 / spec #561).
  Task transitionTo(TaskStatus next, {Object? blockedReason = const _Unset()}) {
    final now = DateTime.now();
    return copyWith(
      status: next,
      statusChangedAt: now,
      statusPendingPush: true,
      completedAt: next == TaskStatus.done ? now : null,
      updatedAt: now,
      syncStatus: syncStatus == SyncStatus.localOnly
          ? SyncStatus.localOnly
          : SyncStatus.pendingSync,
      blockedReason: blockedReason,
    );
  }

  Task markPendingSync() {
    return copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  Task markSynced() => copyWith(
        syncStatus: SyncStatus.synced,
        statusPendingPush: false,
      );

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
  String toString() => 'Task(id: $id, title: $title, status: $status)';
}

class _Unset {
  const _Unset();
}
