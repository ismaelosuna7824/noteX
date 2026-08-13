import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../application/use_cases/task/resolve_task_note_link_use_case.dart';
import '../../application/use_cases/timer/get_time_entries_use_case.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/task.dart';
import '../../domain/entities/time_entry.dart';
import '../../domain/value_objects/note_link_resolution.dart';
import '../../domain/value_objects/task_status.dart';
import '../../domain/value_objects/task_transition_outcome.dart';
import '../state/app_state.dart';
import '../state/task_state.dart';
import '../state/theme_state.dart';
import '../state/timer_state.dart';
import 'animated_dialog.dart';
import 'note_markdown_editor.dart';

/// Kanban view of tasks, grouped into four columns by [TaskStatus].
///
/// An additional surface alongside the flat list (task-page's flat list and
/// the home page's "pending today" card are unaffected). Moving a card
/// between columns performs the same transition as an explicit edit — no
/// board-specific rules (spec capability `task-board`) — always through
/// [TaskState.transitionTask], which delegates to
/// [TransitionTaskStatusUseCase] (design D3/D6, the sole producer of
/// transition writes).
class TaskBoard extends StatelessWidget {
  const TaskBoard({
    super.key,
    required this.taskState,
    required this.themeState,
    required this.timerState,
  });

  final TaskState taskState;
  final ThemeState themeState;

  /// Read here only to show a running-timer indicator on the linked task's
  /// card (elapsed time, ticking) — the coverage gap the verify report and
  /// the "Start timer does nothing observable" bug report both named: until
  /// this, starting a timer from the board gave the user no visible
  /// confirmation anything happened. Callers must rebuild [TaskBoard] on
  /// [TimerState] changes (e.g. `ListenableBuilder`/`AnimatedBuilder`) for
  /// the elapsed time to tick.
  final TimerState timerState;

  static const _columns = [
    TaskStatus.todo,
    TaskStatus.doing,
    TaskStatus.blocked,
    TaskStatus.done,
  ];

  static const _columnLabels = {
    TaskStatus.todo: 'To Do',
    TaskStatus.doing: 'Doing',
    TaskStatus.blocked: 'Blocked',
    TaskStatus.done: 'Done',
  };

  /// Tasks for a given column. Todo/Doing pull from every non-deleted task
  /// in that status (backlog tasks included — a null scheduledDate just
  /// means no date badge on the card). Blocked and Done use their own
  /// dedicated buckets:
  /// * Blocked: [TaskState.blocked] (all blocked tasks — no day scoping;
  ///   nothing in the spec says a blocked task should ever roll off).
  /// * Done: [TaskState.completedToday] (completed today, regardless of
  ///   when it was scheduled — spec's "visible until end of day"), PLUS any
  ///   done backlog task (no scheduledDate means no day to roll over from,
  ///   so it stays visible rather than vanishing the moment it's marked
  ///   done via drag). `completedToday` is keyed on `completedAt`
  ///   (repository doc), so a done backlog task can appear in both buckets
  ///   the day it's completed — excluded from the first to avoid a
  ///   duplicate card; the second is its permanent home.
  List<Task> _tasksFor(TaskStatus status) {
    switch (status) {
      case TaskStatus.blocked:
        return taskState.blocked;
      case TaskStatus.done:
        final doneBacklog = taskState.reminders.where(
          (t) => t.status == TaskStatus.done && t.scheduledDate == null,
        );
        final completedWithSchedule = taskState.completedToday.where(
          (t) => t.scheduledDate != null,
        );
        return [...completedWithSchedule, ...doneBacklog];
      case TaskStatus.todo:
      case TaskStatus.doing:
        return taskState.reminders.where((t) => t.status == status).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final status in _columns)
          Expanded(
            child: _BoardColumn(
              status: status,
              label: _columnLabels[status]!,
              tasks: _tasksFor(status),
              taskState: taskState,
              themeState: themeState,
              timerState: timerState,
              isDark: isDark,
              onCreate: status == TaskStatus.todo
                  ? () => showAddTaskDialog(context, taskState, themeState)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Opens the "New Task" dialog. Unlike the flat list's dialog, this one
/// offers a "No date (add to backlog)" toggle — the affordance spec #561's
/// "create a task with no schedule" scenario needed, deliberately kept off
/// the flat list so its tiles never have to render a dateless task (see
/// design D5 / slice-2 apply notes).
Future<void> showAddTaskDialog(
  BuildContext context,
  TaskState taskState,
  ThemeState themeState,
) async {
  final titleController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  bool backlog = false;
  final accentColor = themeState.accentColor;

  await showAnimatedDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'New Task',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    hintText: 'What do you need to do?',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accentColor, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _submitAddTask(
                    ctx,
                    taskState,
                    titleController,
                    backlog ? null : selectedDate,
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: backlog,
                  onChanged: (value) =>
                      setDialogState(() => backlog = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: accentColor,
                  title: const Text(
                    'No date (add to backlog)',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                if (!backlog) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030, 12, 31),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.20)
                              : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                            color: accentColor,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            color: isDark ? Colors.white54 : Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _submitAddTask(
                ctx,
                taskState,
                titleController,
                backlog ? null : selectedDate,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Create'),
            ),
          ],
        );
      },
    ),
  );
}

void _submitAddTask(
  BuildContext dialogContext,
  TaskState taskState,
  TextEditingController titleController,
  DateTime? scheduledDate,
) {
  final title = titleController.text.trim();
  if (title.isEmpty) return;
  taskState.createReminder(title: title, scheduledDate: scheduledDate);
  Navigator.of(dialogContext).pop();
}

// ─────────────────────────────────────────────────────────────────────────
// Board column: a drag target rendering one status bucket.
// ─────────────────────────────────────────────────────────────────────────

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.status,
    required this.label,
    required this.tasks,
    required this.taskState,
    required this.themeState,
    required this.timerState,
    required this.isDark,
    this.onCreate,
  });

  final TaskStatus status;
  final String label;
  final List<Task> tasks;
  final TaskState taskState;
  final ThemeState themeState;
  final TimerState timerState;
  final bool isDark;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final accentColor = themeState.accentColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: DragTarget<Task>(
        onWillAcceptWithDetails: (details) => details.data.status != status,
        onAcceptWithDetails: (details) {
          // Always through TransitionTaskStatusUseCase — see class doc.
          taskState.transitionTask(details.data.id, status);
        },
        builder: (context, candidateData, rejectedData) {
          final highlighted = candidateData.isNotEmpty;
          return Container(
            constraints: const BoxConstraints(minHeight: 200),
            decoration: BoxDecoration(
              color: highlighted
                  ? accentColor.withValues(alpha: 0.08)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.grey.shade50),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: highlighted
                    ? accentColor.withValues(alpha: 0.4)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$label (${tasks.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    if (onCreate != null)
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        tooltip: 'New task',
                        onPressed: onCreate,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No tasks',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white24 : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  )
                else
                  ...tasks.map(
                    (task) => _BoardCard(
                      task: task,
                      taskState: taskState,
                      themeState: themeState,
                      timerState: timerState,
                      isDark: isDark,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// `hh:mm:ss` for a running task's elapsed time, matching the format
/// `timer_page.dart`'s own `_formatDuration` already uses elsewhere in the
/// timer feature.
String _formatCardElapsed(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

// ─────────────────────────────────────────────────────────────────────────
// Board card: draggable, opens the detail dialog on tap.
// ─────────────────────────────────────────────────────────────────────────

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.task,
    required this.taskState,
    required this.themeState,
    required this.timerState,
    required this.isDark,
  });

  final Task task;
  final TaskState taskState;
  final ThemeState themeState;
  final TimerState timerState;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final card = _CardBody(
      task: task,
      themeState: themeState,
      timerState: timerState,
      isDark: isDark,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Draggable<Task>(
        data: task,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 220, child: card),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: card),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showAnimatedDialog<void>(
            context: context,
            builder: (_) => _TaskDetailDialog(
              task: task,
              taskState: taskState,
              accentColor: themeState.accentColor,
            ),
          ),
          child: card,
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.task,
    required this.themeState,
    required this.timerState,
    required this.isDark,
  });

  final Task task;
  final ThemeState themeState;
  final TimerState timerState;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accentColor = themeState.accentColor;
    final date = task.scheduledDate;
    final isDone = task.status == TaskStatus.done;
    final hasReason =
        task.status == TaskStatus.blocked && (task.blockedReason?.trim().isNotEmpty ?? false);
    final runningEntry = timerState.runningEntry;
    final isTimerRunning =
        runningEntry != null && runningEntry.taskId == task.id;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: isDone ? TextDecoration.lineThrough : null,
              color: isDone
                  ? (isDark ? Colors.white38 : Colors.grey.shade400)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          if (isTimerRunning) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_rounded, size: 11, color: accentColor),
                const SizedBox(width: 4),
                Text(
                  _formatCardElapsed(runningEntry.elapsed),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          if (date != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 11, color: accentColor),
                const SizedBox(width: 4),
                Text(
                  '${date.month}/${date.day}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
              ],
            )
          else
            Text(
              'Backlog',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
          if (hasReason) ...[
            const SizedBox(height: 6),
            Text(
              task.blockedReason!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.red.shade200 : Colors.red.shade400,
              ),
            ),
          ],
          if (task.noteIds.isNotEmpty) ...[
            const SizedBox(height: 6),
            // Scan-at-a-glance indicator (decision
            // architecture/task-note-linking-model — "si regresas con el
            // tiempo no lo sabrás"): a user browsing the board can tell
            // which tasks carry documentation without opening each one.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 11,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  task.noteIds.length == 1
                      ? '1 note'
                      : '${task.noteIds.length} notes',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Task detail dialog: title, Markdown description, blockedReason editor.
// ─────────────────────────────────────────────────────────────────────────

class _TaskDetailDialog extends StatefulWidget {
  const _TaskDetailDialog({
    required this.task,
    required this.taskState,
    required this.accentColor,
  });

  final Task task;
  final TaskState taskState;
  final Color accentColor;

  @override
  State<_TaskDetailDialog> createState() => _TaskDetailDialogState();
}

class _TaskDetailDialogState extends State<_TaskDetailDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _blockedReasonController;
  late String _description;

  // Local mirror of the task's linked notes, updated as the user links or
  // unlinks within this dialog session (decision
  // architecture/task-note-linking-model — linking appends and the dialog
  // stays open, so several notes can be linked without reopening it).
  late List<String> _noteIds;
  final Map<String, NoteLinkResolution> _noteResolutions = {};
  bool _loadingNotes = true;

  // The project this task is assigned to — mirrors the noteIds pattern
  // above: a local copy updated as the user reassigns it within this
  // dialog session, so the selector reflects the change immediately
  // without waiting for a full task reload.
  late String? _projectId;

  // Every TimeEntry ever linked to this task (running or stopped),
  // powering "total tracked time" — the settled decision that replaces a
  // pause/resume affordance this app's data model doesn't support (each
  // stretch is its own entry; see TimeEntry.stop's doc).
  List<TimeEntry> _timeEntries = [];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _blockedReasonController =
        TextEditingController(text: widget.task.blockedReason ?? '');
    _description = widget.task.description;
    _noteIds = List<String>.from(widget.task.noteIds);
    _projectId = widget.task.projectId;
    unawaited(_loadLinkedNotes());
    unawaited(_loadTimeEntries());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _blockedReasonController.dispose();
    super.dispose();
  }

  /// Resolves every linked note's affordance state up front (design D9),
  /// each independently — a task with three notes where one is in the
  /// trash must still render the other two normally.
  Future<void> _loadLinkedNotes() async {
    if (_noteIds.isEmpty) {
      if (mounted) setState(() => _loadingNotes = false);
      return;
    }
    final useCase = GetIt.instance<ResolveTaskNoteLinkUseCase>();
    final entries = await Future.wait(
      _noteIds.map((id) async => MapEntry(id, await useCase.execute(id))),
    );
    if (!mounted) return;
    setState(() {
      _noteResolutions
        ..clear()
        ..addEntries(entries);
      _loadingNotes = false;
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    // blockedReason is rendered — and therefore only ever edited — while
    // status == blocked (design D3: retained but hidden otherwise, never
    // destroyed by an edit to an unrelated field).
    final isBlocked = widget.task.status == TaskStatus.blocked;
    if (isBlocked) {
      final reason = _blockedReasonController.text.trim();
      await widget.taskState.updateTask(
        widget.task.id,
        title: title.isEmpty ? null : title,
        description: _description,
        blockedReason: reason.isEmpty ? null : reason,
      );
    } else {
      await widget.taskState.updateTask(
        widget.task.id,
        title: title.isEmpty ? null : title,
        description: _description,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// Loads every TimeEntry ever linked to this task, for the "total
  /// tracked time" figure. Re-run after start/stop so the total (and the
  /// list a running-entry lookup would otherwise miss) stays current.
  Future<void> _loadTimeEntries() async {
    final entries = await GetIt.instance<GetTimeEntriesUseCase>()
        .getByTaskId(widget.task.id);
    if (!mounted) return;
    setState(() => _timeEntries = entries);
  }

  /// Starts a timer linked to this task, inheriting [_projectId] — the
  /// task's own assigned project, not the timer bar's draft (settled
  /// decision: "link con los proyectos del timer"). The task write is
  /// best-effort — a failure never blocks the timer, and is surfaced here
  /// as a non-blocking SnackBar rather than swallowed.
  ///
  /// Unlike the old one-way "Start timer" button, this no longer pops the
  /// dialog: the user asked to control the timer FROM here, so the dialog
  /// stays open to watch and stop it (settled decision).
  Future<void> _startTimer() async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await GetIt.instance<TimerState>().startTimer(
      taskId: widget.task.id,
      description: widget.task.title,
      projectId: _projectId,
    );
    if (!mounted) return;
    if (outcome == TaskTransitionOutcome.failed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Timer started, but the task status could not be updated.',
          ),
        ),
      );
    }
    await _loadTimeEntries();
  }

  /// Stops the timer running for this task — the "pause" half of the
  /// control. Ends the current TimeEntry stretch; resuming later starts a
  /// fresh one rather than reopening this one (settled decision: separate
  /// stretches record when work actually happened, matching Toggl).
  Future<void> _stopTimer() async {
    await GetIt.instance<TimerState>().stopTimer();
    if (!mounted) return;
    await _loadTimeEntries();
  }

  /// Reassigns this task's project — a deliberate edit, never a status
  /// change (design D3), persisted through [TaskState.setTaskProject]
  /// rather than [TaskState.updateTask]/`_save` so it takes effect
  /// immediately, independent of the title/description Save button.
  Future<void> _assignProject(String? projectId) async {
    setState(() => _projectId = projectId);
    await widget.taskState.setTaskProject(widget.task.id, projectId);
  }

  /// Opens the note picker and appends the chosen note to this task's
  /// links (`LinkNoteToTaskUseCase` via [TaskState.linkNoteToTask] — a task
  /// carries N notes, decision architecture/task-note-linking-model).
  /// Stays open rather than popping, so several notes can be linked in one
  /// session — the picker itself already excludes notes already linked by
  /// deduplicating on selection.
  Future<void> _linkNote() async {
    final appState = GetIt.instance<AppState>();
    final selected = await showDialog<Note>(
      context: context,
      builder: (_) => _NotePickerDialog(
        notes: appState.notes,
        accentColor: widget.accentColor,
      ),
    );
    if (selected == null || !mounted) return;
    if (_noteIds.contains(selected.id)) return;

    final updated =
        await widget.taskState.linkNoteToTask(widget.task.id, selected.id);
    if (!mounted) return;
    setState(() => _noteIds = List<String>.from(updated?.noteIds ?? [
          ..._noteIds,
          selected.id,
        ]));

    final resolution =
        await GetIt.instance<ResolveTaskNoteLinkUseCase>().execute(
      selected.id,
    );
    if (!mounted) return;
    setState(() => _noteResolutions[selected.id] = resolution);
  }

  /// Removes [noteId] from this task's links only — every other linked
  /// note is untouched (`UnlinkNoteFromTaskUseCase` via
  /// [TaskState.unlinkNoteFromTask]).
  Future<void> _unlinkNote(String noteId) async {
    final updated =
        await widget.taskState.unlinkNoteFromTask(widget.task.id, noteId);
    if (!mounted) return;
    setState(() {
      _noteIds = List<String>.from(
        updated?.noteIds ?? (List<String>.from(_noteIds)..remove(noteId)),
      );
      _noteResolutions.remove(noteId);
    });
  }

  /// Resolves and opens the note at [noteId] through the three affordance
  /// states (design D9): found and live → navigate to it; found and
  /// soft-deleted → offer to restore, then open; not found → offer to
  /// unlink just this entry. Always via [ResolveTaskNoteLinkUseCase], never
  /// the deletedAt-filtered in-memory note list.
  Future<void> _openNote(String noteId) async {
    final resolution = _noteResolutions[noteId] ??
        await GetIt.instance<ResolveTaskNoteLinkUseCase>().execute(noteId);
    if (!mounted) return;

    switch (resolution.status) {
      case NoteLinkStatus.found:
        final navigator = Navigator.of(context);
        await GetIt.instance<AppState>().selectNote(resolution.note!);
        navigator.pop();
      case NoteLinkStatus.inTrash:
        final restore = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Note in trash'),
            content: Text(
              '"${resolution.note!.title}" is in the trash. Restore it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Restore'),
              ),
            ],
          ),
        );
        if (restore != true || !mounted) return;
        final navigator = Navigator.of(context);
        final appState = GetIt.instance<AppState>();
        await appState.restoreNote(resolution.note!.id);
        final restored = await GetIt.instance<ResolveTaskNoteLinkUseCase>()
            .execute(noteId);
        if (restored.status == NoteLinkStatus.found) {
          await appState.selectNote(restored.note!);
        }
        navigator.pop();
      case NoteLinkStatus.missing:
        final unlink = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Note not found'),
            content: const Text('This linked note no longer exists.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Unlink'),
              ),
            ],
          ),
        );
        if (unlink == true && mounted) {
          await _unlinkNote(noteId);
        }
    }
  }

  /// Every linked-note row is exactly this tall (44px content + 4px of
  /// vertical padding = a comfortable 44×44 minimum tap target for the
  /// unlink button). The notes list viewport below is always sized to a
  /// whole multiple of this constant, so it cuts BETWEEN rows and never
  /// clips one mid-height.
  static const double _noteRowHeight = 48;

  /// Cap on how many rows are visible before the list scrolls internally.
  static const int _maxVisibleNoteRows = 3;

  /// Quiet, muted section label — structures the dialog into groups
  /// (Task / Notes / Description) without shouting over their content.
  Widget _sectionHeader(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? Colors.white38 : Colors.grey.shade500,
        ),
      ),
    );
  }

  /// Renders every linked note as its own row (open + unlink affordances),
  /// plus a "Link (another) note" action — the visibility half of decision
  /// architecture/task-note-linking-model: a list, not a single pill, so a
  /// user can tell exactly which notes a task carries.
  ///
  /// Uses `ListView.builder` for lazy row construction and a per-row
  /// `ValueKey` (Flutter list guidance) so a row's state survives a
  /// link/unlink reorder. The viewport height is always
  /// `_noteRowHeight * min(count, _maxVisibleNoteRows)` — an exact multiple
  /// of one row, so scrolling only ever exposes a whole row, never half of
  /// one. Once the list overflows that cap, a `Scrollbar` with a permanent
  /// thumb is the unmistakable "there is more" affordance.
  Widget _buildLinkedNotesSection(bool isDark) {
    if (_noteIds.isEmpty) {
      return OutlinedButton.icon(
        onPressed: _linkNote,
        icon: const Icon(Icons.link, size: 16),
        label: const Text('Link note'),
        style: OutlinedButton.styleFrom(
          foregroundColor: widget.accentColor,
          minimumSize: const Size(0, 44),
        ),
      );
    }
    final visibleRows = _noteIds.length < _maxVisibleNoteRows
        ? _noteIds.length
        : _maxVisibleNoteRows;
    final overflowing = _noteIds.length > _maxVisibleNoteRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.grey.shade200,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox(
            height: _noteRowHeight * visibleRows,
            child: Scrollbar(
              thumbVisibility: overflowing,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _noteIds.length,
                itemBuilder: (context, index) {
                  final noteId = _noteIds[index];
                  return _LinkedNoteRow(
                    key: ValueKey(noteId),
                    resolution: _noteResolutions[noteId],
                    loading:
                        _loadingNotes && !_noteResolutions.containsKey(noteId),
                    isDark: isDark,
                    accentColor: widget.accentColor,
                    onOpen: () => _openNote(noteId),
                    onUnlink: () => _unlinkNote(noteId),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _linkNote,
          icon: const Icon(Icons.add_link, size: 16),
          label: const Text('Link another note'),
          style: TextButton.styleFrom(
            foregroundColor: widget.accentColor,
            minimumSize: const Size(0, 44),
          ),
        ),
      ],
    );
  }

  /// Project selector — "No Project" plus every project [TimerState] knows
  /// about (settled decision: "link con los proyectos del timer"). Persists
  /// immediately through [_assignProject]; unlike title/description, a
  /// project change does not wait for the Save button.
  ///
  /// If [_projectId] points at a project [TimerState.projects] doesn't
  /// carry (soft-deleted — mirrors a trashed linked note's degrade-the-
  /// display-keep-the-data rule, design D9), a synthetic "Deleted project"
  /// entry keeps the dropdown's selected value valid instead of throwing on
  /// Flutter's "exactly one item must match" assertion, or silently
  /// clearing the reference.
  Widget _buildProjectSelector(bool isDark) {
    final timerState = GetIt.instance<TimerState>();
    final projects = timerState.projects;
    final isDangling =
        _projectId != null && timerState.projectForId(_projectId) == null;
    final mutedColor = isDark ? Colors.white54 : Colors.grey.shade600;

    return Row(
      children: [
        Icon(Icons.folder_outlined, size: 15, color: mutedColor),
        const SizedBox(width: 8),
        DropdownButton<String?>(
          value: _projectId,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: TextStyle(fontSize: 12.5, color: mutedColor),
          onChanged: _assignProject,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('No Project'),
            ),
            if (isDangling)
              DropdownMenuItem<String?>(
                value: _projectId,
                child: const Text('Deleted project'),
              ),
            for (final p in projects)
              DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
          ],
        ),
      ],
    );
  }

  /// The timer control — replaces the old one-way "Start timer" button.
  /// Stateful: shows Start when no timer is running for this task; shows
  /// live-ticking Stop + the running total when one is (settled decision:
  /// control the timer from here, don't just fire it and forget it).
  /// Scoped in its own [ListenableBuilder] so only this small subtree
  /// rebuilds every second a timer runs anywhere, driven by
  /// [TimerState]'s own ticker.
  Widget _buildTimerControl(bool isDark) {
    return ListenableBuilder(
      listenable: GetIt.instance<TimerState>(),
      builder: (context, _) {
        final timerState = GetIt.instance<TimerState>();
        final runningEntry = timerState.runningEntry;
        final isRunningHere =
            runningEntry != null && runningEntry.taskId == widget.task.id;
        // Every entry's own elapsed getter is already live for a running
        // entry ((endTime ?? now) - startTime), so this total ticks along
        // with the rebuild this ListenableBuilder triggers — no separate
        // "add the live delta" branch needed.
        final total = _timeEntries.fold(
          Duration.zero,
          (Duration acc, e) => acc + e.elapsed,
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: isRunningHere ? _stopTimer : _startTimer,
              icon: Icon(
                isRunningHere ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 18,
              ),
              label: Text(isRunningHere ? 'Stop' : 'Start timer'),
            ),
            const SizedBox(width: 8),
            Text(
              'Total: ${_formatCardElapsed(total)}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Task-identity section: title, project, the timer control (lifted out
  /// of the footer — it acts on the TASK, not the dialog, settled
  /// decision), and — only while blocked — the blocked-reason editor.
  Widget _buildTaskSection(bool isDark, bool isBlocked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Task', isDark),
        TextField(
          controller: _titleController,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          decoration: InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildProjectSelector(isDark),
        const SizedBox(height: 8),
        _buildTimerControl(isDark),
        if (isBlocked) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _blockedReasonController,
            decoration: InputDecoration(
              labelText: 'Blocked reason',
              hintText: 'What is this waiting on?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Notes section — the count lives in the header itself ("Notes · 3"),
  /// so the list body only ever has to render rows, not also announce how
  /// many there are.
  Widget _buildNotesSection(bool isDark) {
    final header =
        _noteIds.isEmpty ? 'Notes' : 'Notes · ${_noteIds.length}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(header, isDark),
        _buildLinkedNotesSection(isDark),
      ],
    );
  }

  /// Description section — the Markdown editor. The dialog's own total
  /// height (see `build`) is sized generously enough that this Expanded
  /// slot naturally lands well above `_kMinEditorHeight`, giving the
  /// editor a sensible minimum without fighting Expanded's own tight
  /// constraint (a `ConstrainedBox(minHeight:...)` inside an `Expanded`
  /// cannot force extra space — it only produces a render overflow when
  /// the leftover space is smaller than the minimum).
  Widget _buildDescriptionSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Description', isDark),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: NoteMarkdownEditor(
              initialContent: widget.task.description,
              toolbar: EditorToolbarProfile.minimal,
              onChanged: (value) => _description = value,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBlocked = widget.task.status == TaskStatus.blocked;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: SizedBox(
        width: 560,
        height: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTaskSection(isDark, isBlocked),
            const SizedBox(height: 24),
            _buildNotesSection(isDark),
            const SizedBox(height: 24),
            Expanded(child: _buildDescriptionSection(isDark)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: widget.accentColor),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One row in the task detail dialog's linked-notes list — one of three
/// affordance states (design D9): found (open), inTrash (open → offers
/// restore) or missing (open → offers unlink). Always paired with its own
/// unlink button, independent of the other linked notes.
class _LinkedNoteRow extends StatelessWidget {
  const _LinkedNoteRow({
    super.key,
    required this.resolution,
    required this.loading,
    required this.isDark,
    required this.accentColor,
    required this.onOpen,
    required this.onUnlink,
  });

  final NoteLinkResolution? resolution;
  final bool loading;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onOpen;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final mutedColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final isMissing = resolution?.status == NoteLinkStatus.missing;
    final IconData icon;
    final String label;
    switch (resolution?.status) {
      case NoteLinkStatus.found:
        icon = Icons.description_outlined;
        label = resolution!.note!.title.isEmpty
            ? 'Untitled'
            : resolution!.note!.title;
      case NoteLinkStatus.inTrash:
        icon = Icons.delete_outline;
        label = '${resolution!.note!.title.isEmpty ? 'Untitled' : resolution!.note!.title} (in trash)';
      case NoteLinkStatus.missing:
        icon = Icons.link_off;
        label = 'Note not found';
      case null:
        icon = Icons.description_outlined;
        label = loading ? 'Loading…' : 'Note';
    }

    // A broken link must read as visually distinct, never at the same
    // weight as a normal note (diagnosed problem #4) — and must not rely
    // on colour alone: italic style + a muted-warning tint + an explicit
    // "Remove" tooltip are three independent signals, not one.
    final rowColor = isMissing
        ? (isDark ? Colors.red.shade200 : Colors.red.shade400)
        : mutedColor;

    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isMissing
              ? (isDark ? Colors.red.withValues(alpha: 0.10) : Colors.red.shade50)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 15, color: rowColor),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: loading ? null : onOpen,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: rowColor,
                      fontStyle: isMissing ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 15),
                tooltip: isMissing ? 'Remove broken link' : 'Unlink',
                splashRadius: 16,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                onPressed: onUnlink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Note picker: search-and-select dialog for linking a note to a task.
//
// Follows the filtering/sorting conventions established by
// MentionPickerHost.mentionCandidates (exclude trashed notes, newest-first)
// and MentionOverlay's per-row rendering (icon + title, "Untitled"
// fallback) — the same note-selection UX the @mention flow already uses,
// adapted from an inline composing overlay to a modal dialog, since linking
// a task is a deliberate button press rather than a token being typed.
// ─────────────────────────────────────────────────────────────────────────

class _NotePickerDialog extends StatefulWidget {
  const _NotePickerDialog({required this.notes, required this.accentColor});

  final List<Note> notes;
  final Color accentColor;

  @override
  State<_NotePickerDialog> createState() => _NotePickerDialogState();
}

class _NotePickerDialogState extends State<_NotePickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Excludes trashed notes (same rule as `MentionPickerHost.mentionCandidates`)
  /// and sorts newest-first; then filters by the search query, if any.
  List<Note> get _filtered {
    final candidates = widget.notes.where((n) => n.deletedAt == null).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_query.isEmpty) return candidates;
    final q = _query.toLowerCase();
    return candidates
        .where((n) => n.title.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final results = _filtered;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Link a note',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 360,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search notes…',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'No notes found',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              isDark ? Colors.white38 : Colors.grey.shade500,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final note = results[index];
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(note),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.note_outlined,
                                  size: 16,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    note.title.isEmpty
                                        ? 'Untitled'
                                        : note.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
