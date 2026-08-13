import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/task.dart';
import '../../domain/value_objects/task_status.dart';
import '../../application/use_cases/task/create_task_use_case.dart';
import '../../application/use_cases/task/get_tasks_use_case.dart';
import '../../application/use_cases/task/link_note_to_task_use_case.dart';
import '../../application/use_cases/task/transition_task_status_use_case.dart';
import '../../application/use_cases/task/unlink_note_from_task_use_case.dart';
import '../../application/use_cases/task/update_task_use_case.dart';
import '../../application/use_cases/task/delete_task_use_case.dart';

/// Presentation state for the Task feature.
///
/// Manages all tasks and the pending-today subset used by the Home card,
/// plus the blocked and completed-today buckets the Kanban board needs.
class TaskState extends ChangeNotifier {
  final CreateTaskUseCase _createReminder;
  final GetTasksUseCase _getReminders;
  final TransitionTaskStatusUseCase _completeReminder;
  final UpdateTaskUseCase _updateReminder;
  final DeleteTaskUseCase _deleteReminder;
  final LinkNoteToTaskUseCase _linkNote;
  final UnlinkNoteFromTaskUseCase _unlinkNote;

  List<Task> _reminders = [];
  List<Task> _pendingToday = [];
  List<Task> _blocked = [];
  List<Task> _completedToday = [];

  TaskState({
    required CreateTaskUseCase createReminder,
    required GetTasksUseCase getReminders,
    required TransitionTaskStatusUseCase completeReminder,
    required UpdateTaskUseCase updateReminder,
    required DeleteTaskUseCase deleteReminder,
    required LinkNoteToTaskUseCase linkNote,
    required UnlinkNoteFromTaskUseCase unlinkNote,
  })  : _createReminder = createReminder,
        _getReminders = getReminders,
        _completeReminder = completeReminder,
        _updateReminder = updateReminder,
        _deleteReminder = deleteReminder,
        _linkNote = linkNote,
        _unlinkNote = unlinkNote;

  // Getters
  List<Task> get reminders => _reminders;
  List<Task> get pendingToday => _pendingToday;
  bool get hasPendingToday => _pendingToday.isNotEmpty;

  /// All non-deleted, `blocked` tasks — the board's Blocked column.
  List<Task> get blocked => _blocked;

  /// `done` tasks completed today — the board's Done column. Separate from
  /// [reminders] so a done task rolls off the board the day after it was
  /// COMPLETED (not the day it was scheduled — a carried-over task keyed on
  /// `scheduledDate` would vanish the instant it was finished), without
  /// being deleted (design's "visible until end of day").
  List<Task> get completedToday => _completedToday;

  /// Load all reminders and every board bucket.
  Future<void> initialize() async {
    await refreshReminders();
  }

  /// Refresh all lists from the database.
  Future<void> refreshReminders() async {
    final now = DateTime.now();
    _reminders = await _getReminders.getAll();
    _pendingToday = await _getReminders.getPending(now);
    _blocked = await _getReminders.getBlocked();
    _completedToday = await _getReminders.getCompletedOn(now);
    notifyListeners();
  }

  /// Create a new task. Null [scheduledDate] creates a backlog task — see
  /// design D5 / spec #561 "create a task with no schedule".
  Future<Task> createReminder({
    required String title,
    DateTime? scheduledDate,
  }) async {
    final reminder = await _createReminder.execute(
      id: const Uuid().v4(),
      title: title,
      scheduledDate: scheduledDate,
    );
    await refreshReminders();
    return reminder;
  }

  /// Mark a reminder as completed. Kept for the existing checkbox call
  /// sites (home card, flat list) — [transitionTask] is the general form.
  Future<void> completeReminder(String id) async {
    await _completeReminder.execute(id, TaskStatus.done);
    await refreshReminders();
  }

  /// Move a task to [next]. The board's drag-to-column gesture is the only
  /// caller today; it always goes through [TransitionTaskStatusUseCase]
  /// (design D3/D6 — the sole producer of transition writes), never
  /// writing status directly.
  Future<Task?> transitionTask(String id, TaskStatus next) async {
    final result = await _completeReminder.execute(id, next);
    await refreshReminders();
    return result;
  }

  /// Update a task's title, description, or blockedReason. Omit
  /// [blockedReason] to leave it untouched (e.g. editing description while
  /// not blocked); pass a value to set it, `null` to clear it — only a
  /// deliberate edit reaches here (design D3).
  ///
  /// Note linking/unlinking is NOT covered here — see [linkNoteToTask] and
  /// [unlinkNoteFromTask] (decision architecture/task-note-linking-model).
  /// A note link is an append/remove on a list, not a field replacement,
  /// so it does not fit this method's "omit vs. set vs. clear" shape.
  ///
  /// [blockedReason]'s sentinel default is resolved here, not forwarded —
  /// [UpdateTaskUseCase] has its own private `_Unset`, a different type per
  /// file (see `update_task_use_case.dart`). Forwarding this class's
  /// sentinel instance into that check would be `false` for a foreign
  /// instance and throw on the cast, so the parameter is either passed
  /// with a resolved value or omitted from the call entirely, letting the
  /// use case's own default apply — never passed as this class's sentinel.
  Future<Task?> updateTask(
    String id, {
    String? title,
    String? description,
    Object? blockedReason = const _Unset(),
  }) async {
    final hasBlockedReason = blockedReason is! _Unset;

    final result = hasBlockedReason
        ? await _updateReminder.execute(
            id,
            title: title,
            description: description,
            blockedReason: blockedReason as String?,
          )
        : await _updateReminder.execute(
            id,
            title: title,
            description: description,
          );
    await refreshReminders();
    return result;
  }

  /// Links [noteId] to task [id], appending it to the task's existing
  /// links (decision architecture/task-note-linking-model — a task carries
  /// N notes). No-op if [noteId] is already linked.
  Future<Task?> linkNoteToTask(String id, String noteId) async {
    final result = await _linkNote.execute(id, noteId);
    await refreshReminders();
    return result;
  }

  /// Unlinks [noteId] from task [id], leaving every other linked note
  /// untouched. No-op if [noteId] is not linked.
  Future<Task?> unlinkNoteFromTask(String id, String noteId) async {
    final result = await _unlinkNote.execute(id, noteId);
    await refreshReminders();
    return result;
  }

  /// Assigns [projectId] to task [id] — pass `null` for "No Project". A
  /// dedicated verb rather than an optional param on [updateTask]: it
  /// always carries a concrete value (the dialog's project selector always
  /// has a definite choice), so no sentinel ever needs resolving here, and
  /// [UpdateTaskUseCase]'s own `_Unset` default is simply never taken —
  /// never touches `status` (design D3; a project change is not a status
  /// change).
  Future<Task?> setTaskProject(String id, String? projectId) async {
    final result = await _updateReminder.execute(id, projectId: projectId);
    await refreshReminders();
    return result;
  }

  /// Reschedules task [id] — pass a value to (re)schedule it, `null` to
  /// send it to the backlog. A dedicated verb rather than an optional
  /// param on [updateTask]: it always carries a concrete value (the
  /// dialog's date picker/clear action always has a definite choice),
  /// same "always concrete, never this class's sentinel" shape as
  /// [setTaskProject] — never touches `status` (design D3; a schedule
  /// change is not a status change). Normalization to local noon happens
  /// inside [UpdateTaskUseCase] (via `Task.normalizeScheduledDate`), not
  /// here, so every caller gets the same guarantee.
  Future<Task?> setTaskScheduledDate(String id, DateTime? scheduledDate) async {
    final result =
        await _updateReminder.execute(id, scheduledDate: scheduledDate);
    await refreshReminders();
    return result;
  }

  /// Soft-delete a reminder.
  Future<void> deleteReminder(String id) async {
    await _deleteReminder.execute(id);
    await refreshReminders();
  }
}

// Private sentinel distinguishing "omitted" from "explicitly passed null".
// Per-file private class — NEVER forwarded across a file boundary as-is (see
// updateTask's doc above for why: UpdateTaskUseCase has its own distinct
// _Unset, and a foreign instance fails its `is _Unset` check silently).
// Resolved to a concrete value or omitted from the call here, matching the
// pattern in update_task_use_case.dart.
class _Unset {
  const _Unset();
}
