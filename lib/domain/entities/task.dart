import 'dart:collection';

import '../value_objects/sync_status.dart';
import '../value_objects/task_status.dart';

/// Core domain entity representing a task.
///
/// Tasks have a title and an optional scheduled date. A task with no date
/// lives only in the backlog (design D5 / spec #561). Uncompleted, dated
/// tasks accumulate — they carry over to the next day until marked complete.
///
/// `status` is the single source of truth for a task's lifecycle state —
/// see design D3. There is no independent `isCompleted` boolean: [isDone]
/// is derived, so it cannot drift from [status].
class Task {
  final String id;
  final String title;

  /// Null means the task has no date and lives only in the backlog.
  /// See design D5 / spec #561 "create a task with no schedule".
  final DateTime? scheduledDate;
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

  /// Links to zero or more notes — a task's accumulating "mini
  /// documentation" (decision architecture/task-note-linking-model). No
  /// foreign key — see design D9; each id is resolved through
  /// [ResolveTaskNoteLinkUseCase], never a deletedAt-filtered list, so a
  /// note in the trash degrades gracefully instead of vanishing silently.
  /// Order-preserving and deduplicated — see [copyWith], [linkNote].
  ///
  /// Supersedes the single, nullable `noteId` the original design used.
  /// That field's storage column (`note_id`) is kept, deprecated and
  /// unused, on the schema — see schema v20 / decision
  /// architecture/task-note-linking-model.
  final List<String> noteIds;
  final String? externalProvider;
  final String? externalId;
  final String? externalUrl;
  final String? externalCachedTitle;
  final DateTime? externalLastSyncedAt;

  /// Links this task to one of the timer feature's projects. No foreign
  /// key locally — mirrors [noteIds]'s no-FK rationale (design D9) — but,
  /// unlike a note, a [Project] is only ever soft-deleted (see
  /// `DeleteProjectUseCase`), never permanently removed, so the Supabase
  /// mapping DOES use a real foreign key (see
  /// `task_supabase_mapper.dart`/`supabase_v21_task_project.sql`). A task
  /// pointing at a since-deleted project keeps the id — degrade the
  /// display, keep the data, same as a trashed linked note.
  ///
  /// Never touched by [transitionTo]: a project assignment is a deliberate
  /// edit, not a status change (see `TaskState.setTaskProject`).
  final String? projectId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String? userId;

  const Task({
    required this.id,
    required this.title,
    this.scheduledDate,
    this.status = TaskStatus.todo,
    this.statusChangedAt,
    this.statusPendingPush = false,
    this.completedAt,
    this.description = '',
    this.blockedReason,
    this.noteIds = const [],
    this.externalProvider,
    this.externalId,
    this.externalUrl,
    this.externalCachedTitle,
    this.externalLastSyncedAt,
    this.projectId,
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
    // Null creates a backlog task — see design D5 / spec #561.
    DateTime? scheduledDate,
    String? userId,
  }) {
    final now = DateTime.now();
    return Task(
      id: id,
      title: title,
      scheduledDate: scheduledDate == null
          ? null
          : DateTime(
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

  /// A backlog task (null [scheduledDate]) never matches any date.
  bool isForDate(DateTime date) {
    final sd = scheduledDate;
    if (sd == null) return false;
    return sd.year == date.year &&
        sd.month == date.month &&
        sd.day == date.day;
  }

  Task copyWith({
    String? title,
    Object? scheduledDate = const _Unset(),
    TaskStatus? status,
    Object? statusChangedAt = const _Unset(),
    bool? statusPendingPush,
    Object? completedAt = const _Unset(),
    String? description,
    Object? blockedReason = const _Unset(),
    Object? noteIds = const _Unset(),
    Object? externalProvider = const _Unset(),
    Object? externalId = const _Unset(),
    Object? externalUrl = const _Unset(),
    Object? externalCachedTitle = const _Unset(),
    Object? externalLastSyncedAt = const _Unset(),
    Object? projectId = const _Unset(),
    DateTime? updatedAt,
    int? version,
    Object? deletedAt = const _Unset(),
    SyncStatus? syncStatus,
    Object? userId = const _Unset(),
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      scheduledDate: scheduledDate is _Unset
          ? this.scheduledDate
          : scheduledDate as DateTime?,
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
      // Deduplicated, order-preserving — passing the same id twice (or an
      // id already present) never produces a duplicate entry. `.cast()`,
      // not a direct `as List<String>`, so a literal like `const []`
      // (reified as `List<dynamic>` without an element-type context) casts
      // safely instead of throwing on the exact-type check `as` performs.
      noteIds: noteIds is _Unset
          ? this.noteIds
          : List<String>.unmodifiable(
              LinkedHashSet<String>.from((noteIds as List).cast<String>()),
            ),
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
      projectId: projectId is _Unset ? this.projectId : projectId as String?,
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

  /// Returns a copy with [id] appended to [noteIds] — the "link a note"
  /// affordance (decision architecture/task-note-linking-model: N notes,
  /// not one). No-op — returns `this` — if [id] is already linked, so
  /// re-linking the same note never creates a duplicate entry.
  Task linkNote(String id) {
    if (noteIds.contains(id)) return this;
    return copyWith(noteIds: [...noteIds, id]);
  }

  /// Returns a copy with [id] removed from [noteIds] — the "unlink" half of
  /// the affordance. No-op — returns `this` — if [id] is not linked.
  Task unlinkNote(String id) {
    if (!noteIds.contains(id)) return this;
    return copyWith(noteIds: noteIds.where((n) => n != id).toList());
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
