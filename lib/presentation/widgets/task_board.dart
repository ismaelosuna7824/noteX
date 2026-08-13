import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../application/use_cases/create_note_use_case.dart';
import '../../application/use_cases/task/resolve_task_note_link_use_case.dart';
import '../../application/use_cases/timer/get_time_entries_use_case.dart';
import '../../application/use_cases/update_note_use_case.dart';
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
import 'project_colors.dart';

/// Kanban view of tasks, grouped into four columns by [TaskStatus].
///
/// An additional surface alongside the flat list (task-page's flat list and
/// the home page's "pending today" card are unaffected). Moving a card
/// between columns performs the same transition as an explicit edit — no
/// board-specific rules (spec capability `task-board`) — always through
/// [TaskState.transitionTask], which delegates to
/// [TransitionTaskStatusUseCase] (design D3/D6, the sole producer of
/// transition writes).
///
/// Every column also honours [ThemeState.taskBoardProjectFilter] — a
/// board-only, persisted filter (same pattern as [ThemeState.taskViewMode])
/// that narrows every bucket, backlog tasks included, to one project (or
/// "No Project") at a time. See [_matchesProjectFilter].
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

  /// [ThemeState.taskBoardProjectFilter] sentinel: show every project's
  /// tasks (default).
  static const String projectFilterAll = 'all';

  /// [ThemeState.taskBoardProjectFilter] sentinel: show only tasks with a
  /// null `projectId`.
  static const String projectFilterNone = 'none';

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
  ///
  /// [ThemeState.taskBoardProjectFilter] is applied last, uniformly, so
  /// every column — backlog tasks included — obeys it identically; a
  /// filtered board never leaks another project's task into any bucket.
  List<Task> _tasksFor(TaskStatus status) {
    final List<Task> tasks;
    switch (status) {
      case TaskStatus.blocked:
        tasks = taskState.blocked;
      case TaskStatus.done:
        final doneBacklog = taskState.reminders.where(
          (t) => t.status == TaskStatus.done && t.scheduledDate == null,
        );
        final completedWithSchedule = taskState.completedToday.where(
          (t) => t.scheduledDate != null,
        );
        tasks = [...completedWithSchedule, ...doneBacklog];
      case TaskStatus.todo:
      case TaskStatus.doing:
        tasks = taskState.reminders.where((t) => t.status == status).toList();
    }
    return tasks.where(_matchesProjectFilter).toList();
  }

  /// Matches [ThemeState.taskBoardProjectFilter]: [projectFilterAll] keeps
  /// everything, [projectFilterNone] keeps only a null `projectId`, and any
  /// other value is treated as a project id to match exactly.
  bool _matchesProjectFilter(Task task) {
    final filter = themeState.taskBoardProjectFilter;
    if (filter == projectFilterAll) return true;
    if (filter == projectFilterNone) return task.projectId == null;
    return task.projectId == filter;
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
///
/// On a successful create, [_submitAddTask] closes this dialog and opens
/// the newly created task's own detail dialog immediately via
/// [showTaskDetailDialog] — the settled decision that the user should
/// never have to find the new card on the board and click it themselves.
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
          // Same theme fix as every other dialog in this feature (task
          // detail dialog, note modals, project dialogs) — the app's own
          // dark-neutral surface, not AlertDialog's
          // `ColorScheme.fromSeed`-derived default, which reads as an
          // off-theme brown against this app's gold accent. This dialog
          // was simply missed in the original sweep.
          backgroundColor: Color.alphaBlend(
            themeState.editorBgColor.withValues(alpha: 0.96),
            isDark ? Colors.black : Colors.white,
          ),
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
                  onSubmitted: (_) => unawaited(_submitAddTask(
                    context,
                    ctx,
                    taskState,
                    themeState,
                    titleController,
                    backlog ? null : selectedDate,
                  )),
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
              onPressed: () => unawaited(_submitAddTask(
                context,
                ctx,
                taskState,
                themeState,
                titleController,
                backlog ? null : selectedDate,
              )),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                // Same fix as the accent-coloured buttons elsewhere (task
                // detail dialog's restore/unlink, _CreateProjectDialog's
                // own Create button): left to the ambient theme, the label
                // resolves against `colorScheme.onPrimary` (the SEED's
                // tonal primary), not the literal accentColor used as the
                // background, which is why it read muted.
                foregroundColor: accentColor.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
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

/// Opens the task detail dialog for [task] — the single entry point every
/// caller must use (the board card's own tap gesture below, and the timer
/// page's "open the task this entry belongs to" affordance) so there is
/// exactly one dialog implementation, never a duplicate copy of it.
///
/// [surfaceColor] is the app's own dark-neutral surface
/// (`ThemeState.editorBgColor`) — see [_TaskDetailDialog.surfaceColor]'s doc
/// for why the dialog needs it explicitly rather than falling back to the
/// ambient [Theme].
Future<void> showTaskDetailDialog(
  BuildContext context,
  Task task,
  TaskState taskState,
  Color accentColor, {
  required Color surfaceColor,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _TaskDetailDialog(
      task: task,
      taskState: taskState,
      accentColor: accentColor,
      surfaceColor: surfaceColor,
    ),
  );
}

/// Creates the task, closes the create dialog, then opens the REAL created
/// task's own detail dialog immediately via [showTaskDetailDialog] — the
/// same single entry point every other caller uses, never a
/// locally-constructed stand-in, so the detail dialog's own save-on-close
/// path always writes against the actual persisted id. [context] is the
/// board's own context (captured by [showAddTaskDialog] before the create
/// dialog opened) — it outlives [dialogContext], which is popped first. On
/// failure, nothing opens and the error is surfaced via `SnackBar`, the
/// same convention [_TaskDetailDialogState._closeDialog] already
/// established for a save failure — the create dialog is left open so the
/// user's typed title/date are not silently discarded.
Future<void> _submitAddTask(
  BuildContext context,
  BuildContext dialogContext,
  TaskState taskState,
  ThemeState themeState,
  TextEditingController titleController,
  DateTime? scheduledDate,
) async {
  final title = titleController.text.trim();
  if (title.isEmpty) return;

  final messenger = ScaffoldMessenger.of(context);
  final Task created;
  try {
    created =
        await taskState.createReminder(title: title, scheduledDate: scheduledDate);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not create task: $e')),
    );
    return;
  }

  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
  if (!context.mounted) return;
  await showTaskDetailDialog(
    context,
    created,
    taskState,
    themeState.accentColor,
    surfaceColor: themeState.editorBgColor,
  );
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
          onTap: () => showTaskDetailDialog(
            context,
            task,
            taskState,
            themeState.accentColor,
            surfaceColor: themeState.editorBgColor,
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
    required this.surfaceColor,
  });

  final Task task;
  final TaskState taskState;
  final Color accentColor;

  /// The app's own dark-neutral surface (`ThemeState.editorBgColor`) — the
  /// colour every OTHER surface in this app (the editor, panels, the
  /// timer's `TimeEntryEditor` dialog) actually renders on. Threaded in
  /// explicitly rather than left to `AlertDialog`'s own default, which
  /// resolves against `Theme.of(context).colorScheme.surfaceContainerHigh`
  /// — a tone generated by `ColorScheme.fromSeed(seedColor: accentColor)`.
  /// That generated tone carries the ACCENT's own hue (Material 3's neutral
  /// palette is a low-chroma rotation of the seed hue, not a fixed grey),
  /// so a warm accent (e.g. this app's gold/yellow default) produces a
  /// visibly warm/brownish dialog background — while every other surface
  /// in the app stays a neutral dark navy, because it reads [surfaceColor]
  /// instead of the ambient [ColorScheme]. This mismatch was the root cause
  /// of "the modal doesn't follow the app's theme" — see
  /// `time_entry_editor.dart`'s `AlertDialog.backgroundColor` for the
  /// precedent this follows.
  final Color surfaceColor;

  @override
  State<_TaskDetailDialog> createState() => _TaskDetailDialogState();
}

class _TaskDetailDialogState extends State<_TaskDetailDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _blockedReasonController;
  late String _description;

  /// Drives the linked-notes list AND its [Scrollbar].
  ///
  /// Both must share one controller. Without it the Scrollbar falls back to
  /// the PrimaryScrollController, which a vertical ScrollView only attaches
  /// to by default on MOBILE platforms — so on macOS it finds no
  /// ScrollPosition and asserts on every frame the thumb is visible.
  final ScrollController _notesScrollController = ScrollController();

  /// Explicit focus nodes for the status and project dropdowns — needed to
  /// fix diagnosed problem #1 (a lingering focus rectangle after a
  /// selection).
  ///
  /// `DropdownButton` calls its own `focusNode.requestFocus()` when
  /// opening. While its menu is open, the menu ROUTE's own overlay holds
  /// primary focus instead — so unfocusing inside `onChanged` (which fires
  /// once the route has already popped, but is disposed asynchronously,
  /// still one frame later) has nothing to undo yet: the anchor only
  /// reclaims focus automatically AFTER `onChanged` returns, when Flutter's
  /// focus manager falls back to it as the popped route's overlay is torn
  /// down. A plain `unfocus()`/`canRequestFocus` toggle inside `onChanged`
  /// therefore runs too early and gets silently overridden a frame later.
  /// [_suppressFocusReclaim] instead reacts to that hand-back directly: it
  /// listens for this node actually regaining focus and immediately drops
  /// it again, for a short window after a selection. A keyboard user who
  /// tabs TO the control afterward is unaffected — the listener is gone
  /// well before then.
  final FocusNode _statusFocusNode = FocusNode(debugLabel: 'task-status');
  final FocusNode _projectFocusNode = FocusNode(debugLabel: 'task-project');

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

  // Local mirror of the task's scheduled date, updated as the user
  // (re)schedules or clears it within this dialog session — same "local
  // mirror, persists immediately" shape as [_projectId] above. `null`
  // means backlog. Persisted through [_setScheduledDate] ->
  // [TaskState.setTaskScheduledDate] -> [UpdateTaskUseCase], never
  // [_closeDialog] — a schedule change is a deliberate edit, not one of
  // the fields [_closeDialog] defers to close time, and must never touch
  // `status`.
  late DateTime? _scheduledDate;

  // Local mirror of the task's status, updated as the user changes it via
  // the sidebar status control within this dialog session (mirrors the
  // noteIds/_projectId pattern above). Never written directly — every
  // change flows through [_changeStatus] -> [TaskState.transitionTask] ->
  // [TransitionTaskStatusUseCase] (design D3/D6, the sole producer of
  // transition writes), exactly like the board's drag gesture.
  late TaskStatus _status;

  // Every TimeEntry ever linked to this task (running or stopped),
  // powering "total tracked time" — the settled decision that replaces a
  // pause/resume affordance this app's data model doesn't support (each
  // stretch is its own entry; see TimeEntry.stop's doc).
  List<TimeEntry> _timeEntries = [];

  // Snapshot of the fields this dialog owns and defers to close time
  // (title, description, blockedReason), taken at open time and compared
  // against in [_isDirty]. Normalized the same way [_persistIfDirty]
  // normalizes them before sending, so the comparison matches exactly what
  // would (or would not) be written. Every other field — status, project,
  // scheduledDate, note links — already persists immediately through its
  // own dedicated verb the moment it changes, so it has no snapshot here
  // and never routes through the close-triggered save.
  late final String _originalTitle;
  late final String _originalDescription;
  late final String _originalBlockedReason;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _blockedReasonController =
        TextEditingController(text: widget.task.blockedReason ?? '');
    _description = widget.task.description;
    _noteIds = List<String>.from(widget.task.noteIds);
    _projectId = widget.task.projectId;
    _scheduledDate = widget.task.scheduledDate;
    _status = widget.task.status;
    _originalTitle = widget.task.title.trim();
    _originalDescription = widget.task.description;
    _originalBlockedReason = widget.task.blockedReason?.trim() ?? '';
    unawaited(_loadLinkedNotes());
    unawaited(_loadTimeEntries());
  }

  @override
  void dispose() {
    // Note editing/preview no longer lives inline here — it is its own
    // modal route ([_NoteEditorDialog]), which owns and flushes its own
    // debounce on every dismissal, so there is nothing pending to cancel
    // here.
    _titleController.dispose();
    _blockedReasonController.dispose();
    _notesScrollController.dispose();
    _statusFocusNode.dispose();
    _projectFocusNode.dispose();
    super.dispose();
  }

  /// Reacts to a [DropdownButton]'s automatic "hand focus back to the
  /// anchor" once its menu route finishes popping (see [_statusFocusNode]'s
  /// doc) — the fix for diagnosed problem #1. Call right after a selection
  /// is applied: for a short window afterward, if [node] regains focus, it
  /// is immediately dropped again. The listener removes itself once that
  /// window passes, so it never interferes with a later, legitimate
  /// keyboard/mouse focus on the same control.
  void _suppressFocusReclaim(FocusNode node) {
    void reclaimGuard() {
      if (node.hasFocus) node.unfocus();
    }

    node.addListener(reclaimGuard);
    Future.delayed(const Duration(milliseconds: 500), () {
      node.removeListener(reclaimGuard);
    });
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

  /// True only if a field this dialog actually persists on close (title,
  /// description, or — while blocked — blockedReason) differs from what it
  /// opened with. Deliberately excludes status/project/scheduledDate/note
  /// links: those already persist immediately through their own dedicated
  /// verbs (see [_changeStatus], [_assignProject], [_setScheduledDate],
  /// [_linkNote]/[_unlinkNote]), so merely opening a task to look at it —
  /// touching none of these three fields — must never write. Saving
  /// unconditionally on every close would bump `updatedAt`, flip the row to
  /// `pendingSync`, and generate sync traffic just from opening a task,
  /// which matters more than usual here given this app's sync layer already
  /// carries known defects around row writes.
  bool get _isDirty {
    if (_titleController.text.trim() != _originalTitle) return true;
    if (_description != _originalDescription) return true;
    // blockedReason is rendered — and therefore only ever edited — while
    // status == blocked (design D3: retained but hidden otherwise, never
    // destroyed by an edit to an unrelated field). Uses the LOCAL _status,
    // not widget.task.status — the sidebar status control can change it
    // within this same dialog session, before the dialog closes.
    if (_status == TaskStatus.blocked &&
        _blockedReasonController.text.trim() != _originalBlockedReason) {
      return true;
    }
    return false;
  }

  /// Persists title/description/blockedReason — but only when [_isDirty] —
  /// then closes. This is the SINGLE path every way of closing this dialog
  /// funnels through (the header X below, and the barrier/Escape via the
  /// `PopScope` in [build]), replacing the old explicit Save/Cancel
  /// footer (this dialog's reference model — a Jira issue modal — has
  /// neither: edits persist and the dialog just closes). A save failure is
  /// surfaced via `SnackBar` rather than swallowed — there is no Cancel to
  /// fall back on, so silence would mean the user's edit vanished without a
  /// trace.
  Future<void> _closeDialog() async {
    // Note editing/preview no longer shares this dialog's own close path —
    // it is its own modal ([_NoteEditorDialog]) with its own flush-on-
    // dismiss lifecycle, and cannot be open while this dialog's barrier or
    // Escape reaches this method (a topmost modal route intercepts both
    // first). Nothing to flush here on its behalf.
    if (_isDirty) {
      final messenger = ScaffoldMessenger.of(context);
      final title = _titleController.text.trim();
      final isBlocked = _status == TaskStatus.blocked;
      try {
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
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save changes: $e')),
        );
      }
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
  /// rather than [TaskState.updateTask]/[_closeDialog] so it takes effect
  /// immediately, independent of the dialog's save-on-close title/
  /// description/blockedReason flow.
  Future<void> _assignProject(String? projectId) async {
    setState(() => _projectId = projectId);
    await widget.taskState.setTaskProject(widget.task.id, projectId);
  }

  /// Opens a lightweight project-creation dialog directly from the project
  /// selector, so a project can be created without leaving the task
  /// (settled decision: "en project que se puedan crear proyectos desde
  /// ahí también"). Goes through [TimerState.createProject] — which wraps
  /// `CreateProjectUseCase` — never a direct write, mirroring
  /// `timer_page.dart`'s own "New Project" dialog (same fields, same
  /// shared [kProjectColors] palette). An empty/whitespace name does
  /// nothing rather than creating a blank project; Cancel does nothing.
  /// On success, the new project is assigned to this task immediately via
  /// [_assignProject], same as picking an existing one.
  Future<void> _createProjectFromSelector() async {
    final newProjectId = await showAnimatedDialog<String>(
      context: context,
      builder: (_) => _CreateProjectDialog(
        accentColor: widget.accentColor,
        surfaceColor: widget.surfaceColor,
      ),
    );
    if (newProjectId == null || !mounted) return;
    await _assignProject(newProjectId);
  }

  /// Opens a date picker to (re)schedule this task, or `null` to send it
  /// to the backlog. Persists immediately through [_setScheduledDate].
  Future<void> _pickScheduledDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030, 12, 31),
    );
    if (picked == null || !mounted) return;
    await _setScheduledDate(picked);
  }

  /// Persists a schedule change immediately — same "local mirror updates
  /// first, then the dedicated verb persists" shape as [_assignProject].
  /// [date] is passed straight through to [TaskState.setTaskScheduledDate]
  /// — normalization to local noon happens inside `UpdateTaskUseCase`
  /// (`Task.normalizeScheduledDate`), never here, so this control gets the
  /// exact same guarantee [Task.create] does. Never touches `status`.
  Future<void> _setScheduledDate(DateTime? date) async {
    setState(() => _scheduledDate = date);
    await widget.taskState.setTaskScheduledDate(widget.task.id, date);
  }

  /// Changes this task's status from the sidebar control — the one
  /// deliberate new behavior this dialog gains (previously status only
  /// changed by dragging a card between board columns). Always through
  /// [TaskState.transitionTask], which delegates to
  /// [TransitionTaskStatusUseCase] (design D3/D6, the sole producer of
  /// transition writes) — never a direct status write. Reverts the local
  /// display if the transition failed (e.g. the task was deleted
  /// elsewhere) so the control never shows a status that was not actually
  /// persisted.
  Future<void> _changeStatus(TaskStatus next) async {
    if (next == _status) return;
    final previous = _status;
    setState(() => _status = next);
    final result = await widget.taskState.transitionTask(widget.task.id, next);
    if (!mounted) return;
    if (result == null) {
      setState(() => _status = previous);
    }
  }

  /// Creates a brand-new note and links it to this task in one gesture —
  /// additive alongside "Link note"/"Link another note", which stay
  /// exactly as they are. Goes through [CreateNoteUseCase] then
  /// [TaskState.linkNoteToTask] (wrapping `LinkNoteToTaskUseCase`) — never
  /// a direct write to `Task.noteIds` or the notes table, same rule
  /// [_linkNote] already follows. Opens the new note immediately in its own
  /// editor/preview MODAL ([_openNoteEditor]) so the user can start writing
  /// without leaving the task — a create flow that forced them out to the
  /// full editor would defeat the point of asking for this alongside the
  /// preview/edit capability. The new note is empty, so the modal's
  /// preview-by-default surface downgrades to the plain edit field
  /// automatically (see [_NoteEditorDialog]'s doc) and is immediately
  /// typable.
  Future<void> _createLinkedNote() async {
    final note =
        await GetIt.instance<CreateNoteUseCase>().execute(id: const Uuid().v4());
    if (!mounted) return;

    final updated =
        await widget.taskState.linkNoteToTask(widget.task.id, note.id);
    if (!mounted) return;
    setState(() {
      _noteIds =
          List<String>.from(updated?.noteIds ?? [..._noteIds, note.id]);
      // Constructed directly rather than round-tripped through
      // [ResolveTaskNoteLinkUseCase] — the note was just created above, so
      // its "found" status is certain without another DB read.
      _noteResolutions[note.id] = NoteLinkResolution(NoteLinkStatus.found, note);
    });

    await _openNoteEditor(note);
  }

  /// Opens [note] in its own MODAL, layered on top of this task dialog —
  /// the settled decision that BOTH creating and previewing a note are
  /// modals ("para crear la nota estaría bien que fuera un modal como ya lo
  /// haces, y para el preview también"), replacing the old in-place NOTES-
  /// section takeover. See [_NoteEditorDialog]'s doc for the
  /// rendered-by-default contract and its own persistence/flush lifecycle
  /// — entirely separate from this dialog's own save-on-close flow, so
  /// opening or editing a note here never marks the TASK dirty (see
  /// [_isDirty]'s doc).
  ///
  /// Every dismissal returns the freshest (post-flush) [Note] alongside a
  /// flag for whether "Open in full editor" was requested. The freshest
  /// [Note] is used UNCONDITIONALLY to refresh [_noteResolutions] — not
  /// only on the full-editor path — so the next [_openNote] (a reopen from
  /// this same still-open task dialog) reads the just-saved edit instead of
  /// the pre-edit [Note] this method was called with. Without this
  /// refresh, [_noteResolutions] keeps serving the stale cached [Note]
  /// indefinitely, which reads to the user exactly like their edit was
  /// never saved — a stale in-memory read, not data loss (the write itself,
  /// [_NoteEditorDialogState._flush], is unaffected by this fix).
  Future<void> _openNoteEditor(Note note) async {
    final result = await showAnimatedDialog<(Note, bool)>(
      context: context,
      builder: (_) => _NoteEditorDialog(
        note: note,
        accentColor: widget.accentColor,
        surfaceColor: widget.surfaceColor,
      ),
    );
    if (!mounted || result == null) return;
    final (updatedNote, openFullEditor) = result;
    setState(() {
      _noteResolutions[updatedNote.id] =
          NoteLinkResolution(NoteLinkStatus.found, updatedNote);
    });
    if (openFullEditor) {
      await _openInFullEditor(updatedNote);
    }
  }

  /// The secondary "open in full editor" action — demoted, not deleted
  /// (settled decision: still useful for long writing). [note] already
  /// reflects any pending edit — [_NoteEditorDialog] flushes before
  /// requesting this — so this only needs the pre-existing navigate-away
  /// path: [AppState.selectNote] plus closing this task dialog, exactly
  /// like activating a linked note used to work for every note before the
  /// preview/edit modal existed.
  Future<void> _openInFullEditor(Note note) async {
    final navigator = Navigator.of(context);
    await GetIt.instance<AppState>().selectNote(note);
    navigator.pop();
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
        surfaceColor: widget.surfaceColor,
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
  /// states (design D9): found and live → open it in its own editor/preview
  /// modal ([_openNoteEditor], without leaving this task — settled
  /// decision); found and soft-deleted → offer to restore, then open it
  /// the same way (never opens an editable preview of a note still in the
  /// trash); not found → offer to unlink just this entry. Always via
  /// [ResolveTaskNoteLinkUseCase], never the deletedAt-filtered in-memory
  /// note list.
  Future<void> _openNote(String noteId) async {
    final resolution = _noteResolutions[noteId] ??
        await GetIt.instance<ResolveTaskNoteLinkUseCase>().execute(noteId);
    if (!mounted) return;

    switch (resolution.status) {
      case NoteLinkStatus.found:
        await _openNoteEditor(resolution.note!);
      case NoteLinkStatus.inTrash:
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final restore = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            // Same theme fix as the parent task detail dialog (and
            // TimeEntryEditor before it): the app's own dark-neutral
            // surface, not AlertDialog's ColorScheme.fromSeed-derived
            // default — see [_TaskDetailDialog.surfaceColor]'s doc.
            backgroundColor: Color.alphaBlend(
              widget.surfaceColor.withValues(alpha: 0.96),
              isDark ? Colors.black : Colors.white,
            ),
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
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  // Same fix as the accent-coloured buttons elsewhere:
                  // left to the ambient theme, the label resolves against
                  // `colorScheme.onPrimary` (the SEED's tonal primary),
                  // not the literal accentColor used as the background.
                  foregroundColor: widget.accentColor.computeLuminance() >
                          0.5
                      ? Colors.black
                      : Colors.white,
                ),
                child: const Text('Restore'),
              ),
            ],
          ),
        );
        if (restore != true || !mounted) return;
        final appState = GetIt.instance<AppState>();
        await appState.restoreNote(resolution.note!.id);
        final restored = await GetIt.instance<ResolveTaskNoteLinkUseCase>()
            .execute(noteId);
        if (!mounted) return;
        setState(() => _noteResolutions[noteId] = restored);
        if (restored.status == NoteLinkStatus.found) {
          // Restoring makes it live — open it the same way any other live
          // note opens, its own editor/preview modal, rather than the old
          // navigate-away path.
          await _openNoteEditor(restored.note!);
        }
      case NoteLinkStatus.missing:
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final unlink = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            // Same theme fix as above — see [_TaskDetailDialog.surfaceColor].
            backgroundColor: Color.alphaBlend(
              widget.surfaceColor.withValues(alpha: 0.96),
              isDark ? Colors.black : Colors.white,
            ),
            title: const Text('Note not found'),
            content: const Text('This linked note no longer exists.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: widget.accentColor.computeLuminance() >
                          0.5
                      ? Colors.black
                      : Colors.white,
                ),
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
      // `Wrap`, not `Row`: the sidebar column is narrow enough that two
      // full-width-ish buttons side by side can exceed it on a stacked
      // narrow window — same reasoning as [_buildTimerControl]'s Wrap.
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _createLinkedNote,
            icon: const Icon(Icons.note_add_outlined, size: 16),
            label: const Text('New note'),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accentColor,
              minimumSize: const Size(0, 44),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _linkNote,
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Link note'),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accentColor,
              minimumSize: const Size(0, 44),
            ),
          ),
        ],
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
              controller: _notesScrollController,
              thumbVisibility: overflowing,
              child: ListView.builder(
                controller: _notesScrollController,
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
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: _createLinkedNote,
              icon: const Icon(Icons.note_add_outlined, size: 16),
              label: const Text('New note'),
              style: TextButton.styleFrom(
                foregroundColor: widget.accentColor,
                minimumSize: const Size(0, 44),
              ),
            ),
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
        ),
      ],
    );
  }

  /// Project selector — "No Project" plus every project [TimerState] knows
  /// about (settled decision: "link con los proyectos del timer"). Persists
  /// immediately through [_assignProject]; unlike title/description, a
  /// project change does not wait for the dialog to close.
  ///
  /// If [_projectId] points at a project [TimerState.projects] doesn't
  /// carry (soft-deleted — mirrors a trashed linked note's degrade-the-
  /// display-keep-the-data rule, design D9), a synthetic "Deleted project"
  /// entry keeps the dropdown's selected value valid instead of throwing on
  /// Flutter's "exactly one item must match" assertion, or silently
  /// clearing the reference.
  /// Sentinel dropdown value for the "New project…" row — distinct from
  /// every real project id (a UUID), so selecting it can never collide
  /// with an actual project. Never persisted: selecting it opens
  /// [_createProjectFromSelector] instead of calling [_assignProject].
  static const String _newProjectValue = '__new_project__';

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
          focusNode: _projectFocusNode,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: TextStyle(fontSize: 12.5, color: mutedColor),
          onChanged: (value) {
            // Suppress the lingering focus rectangle after a selection
            // (diagnosed problem #1) — see [_projectFocusNode]'s doc for
            // why a plain `unfocus()` here does not stick. A keyboard user
            // tabbing TO the control still sees its own focus ring; only
            // the auto-reclaim once a choice has been made is suppressed.
            _suppressFocusReclaim(_projectFocusNode);
            if (value == _newProjectValue) {
              unawaited(_createProjectFromSelector());
            } else {
              unawaited(_assignProject(value));
            }
          },
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
            DropdownMenuItem<String?>(
              value: _newProjectValue,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 14, color: widget.accentColor),
                  const SizedBox(width: 6),
                  Text(
                    'New project…',
                    style: TextStyle(
                      color: widget.accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
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
        // Wrap, not Row: the sidebar's Details panel column is much
        // narrower than the old single-column dialog was, so the button
        // and the total label must be free to fall onto their own line
        // instead of forcing a `RenderFlex overflow`.
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: isRunningHere ? _stopTimer : _startTimer,
              icon: Icon(
                isRunningHere ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 18,
              ),
              label: Text(isRunningHere ? 'Stop' : 'Start timer'),
            ),
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

  /// The title field — large, prominent and multi-line (wraps instead of
  /// scrolling horizontally), the first thing in the left content column.
  Widget _buildTitleField() {
    return TextField(
      key: const Key('task-detail-title-field'),
      controller: _titleController,
      maxLines: null,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
      decoration: InputDecoration(
        labelText: 'Title',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Notes section — the count lives in the header itself ("Notes · 3"),
  /// so the list body only ever has to render rows, not also announce how
  /// many there are. Always renders the list-and-actions state: creating or
  /// previewing a note no longer takes this section over in place — both
  /// open their own MODAL ([_openNoteEditor]/[_NoteEditorDialog]) layered
  /// on top of this dialog instead (settled decision: "que fuera un modal
  /// como ya lo haces").
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

  /// Description section — the Markdown editor, given real height. When
  /// [height] is omitted (the side-by-side layout), the editor fills the
  /// remaining space of its ancestor `Expanded` — the dialog's own total
  /// height is sized generously enough that this lands well above
  /// `_kMinEditorHeight`, without fighting `Expanded`'s own tight
  /// constraint (a `ConstrainedBox(minHeight:...)` inside an `Expanded`
  /// cannot force extra space — it only produces a render overflow when
  /// the leftover space is smaller than the minimum). When [height] is
  /// given (the stacked layout, inside a `SingleChildScrollView` where
  /// `Expanded` cannot be used — its incoming height is unbounded), the
  /// editor gets that fixed height instead.
  Widget _buildDescriptionSection(bool isDark, {double? height}) {
    final editor = Container(
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
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Description', isDark),
        height != null ? SizedBox(height: height, child: editor) : Expanded(child: editor),
      ],
    );
  }

  /// The left content column: the things the user WRITES — title, then
  /// description. Linked notes now live in the right sidebar (they are a
  /// reference/attachment, like Project or Scheduled date, not prose) — so
  /// the description is the last thing here and its `Expanded` (see below)
  /// can honestly own the full remaining height instead of leaving room for
  /// a section that used to follow it. In the stacked layout ([stacked] =
  /// true, used inside a `SingleChildScrollView`) the description still
  /// gets a fixed height instead of `Expanded`, since `Expanded` requires a
  /// bounded incoming height.
  Widget _buildLeftColumn(bool isDark, {required bool stacked}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitleField(),
        const SizedBox(height: 20),
        stacked
            ? _buildDescriptionSection(isDark, height: 260)
            : Expanded(child: _buildDescriptionSection(isDark)),
      ],
    );
  }

  /// A quiet label/value row for the sidebar's Details panel — a small
  /// muted caption above its value, matching the reference layout's
  /// "things you set" panel.
  Widget _buildDetailRow(String label, Widget value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );
  }

  /// The blocked-reason editor — kept as its own `TextField` (not wrapped
  /// in [_buildDetailRow]'s caption) because its `labelText` already
  /// announces "Blocked reason"; a second caption above it would be a
  /// redundant label for the same field.
  Widget _buildBlockedReasonField() {
    return TextField(
      controller: _blockedReasonController,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: 'Blocked reason',
        hintText: 'What is this waiting on?',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// The scheduled-date control — tap to pick a date (a backlog task gets
  /// one), tap the close icon to clear it back to the backlog. Persists
  /// immediately through [_setScheduledDate], the same "does not wait for
  /// the dialog to close" pattern as the Project selector and status
  /// control — a schedule change is a deliberate edit, distinct from the
  /// title/description/blockedReason save-on-close flow.
  Widget _buildScheduledDateControl(bool isDark) {
    final mutedColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final date = _scheduledDate;
    final label =
        date == null ? 'Backlog' : DateFormat('MMM d, yyyy').format(date);

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => unawaited(_pickScheduledDate()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded, size: 13, color: mutedColor),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(fontSize: 13, color: mutedColor)),
                ],
              ),
            ),
          ),
        ),
        if (date != null)
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            tooltip: 'Clear date (move to backlog)',
            splashRadius: 16,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: EdgeInsets.zero,
            onPressed: () => unawaited(_setScheduledDate(null)),
          ),
      ],
    );
  }

  /// The Details panel: quiet label/value rows for the things the user
  /// SETS rather than writes — Project, Scheduled date (editable: pick to
  /// (re)schedule, clear to send back to the backlog), Blocked reason
  /// (only while blocked — design D3's display-scoping rule: the value
  /// stays in the data, only its ROW is hidden otherwise), and Time
  /// tracked (the timer control). No Notes row here — that count now lives
  /// in the "Notes · N" section header itself, immediately above the
  /// linked-notes list, so it is not duplicated.
  Widget _buildDetailsPanel(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDetailRow('Project', _buildProjectSelector(isDark), isDark),
        _buildDetailRow(
          'Scheduled date',
          _buildScheduledDateControl(isDark),
          isDark,
        ),
        if (_status == TaskStatus.blocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildBlockedReasonField(),
          ),
        _buildDetailRow('Time tracked', _buildTimerControl(isDark), isDark),
      ],
    );
  }

  /// Wraps [_buildDetailsPanel] in a bordered card — the app's existing
  /// subtle-surface treatment (same rounded corners/border already used
  /// elsewhere in this file: the board columns, the notes list, the
  /// description editor), not a new style. Without a real container here,
  /// the whitespace below a short Details panel reads as a rendering fault
  /// rather than intentional spacing; a card that ends where its own
  /// content ends reads as deliberate.
  Widget _buildDetailsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.grey.shade200,
        ),
      ),
      child: _buildDetailsPanel(isDark),
    );
  }

  /// The status control — prominent, at the top of the sidebar (reference
  /// layout). The one deliberate behavior addition this redesign makes:
  /// status can now change from the dialog, not only by dragging a card
  /// between board columns. Always through [_changeStatus] ->
  /// [TaskState.transitionTask] -> [TransitionTaskStatusUseCase] (design
  /// D3/D6) — never a direct status write. Uses the app's own accent
  /// colour, not a new palette — the label text is always visible, so the
  /// colour is a supplementary cue, never the sole signal.
  Widget _buildStatusControl(bool isDark) {
    final accent = widget.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TaskStatus>(
          value: _status,
          focusNode: _statusFocusNode,
          isExpanded: true,
          icon: Icon(Icons.expand_more_rounded, color: accent),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: accent),
          onChanged: (next) {
            // Same focus-reclaim fix as the project selector (diagnosed
            // problem #1) — see [_statusFocusNode]'s doc for why a plain
            // `unfocus()` here does not stick.
            _suppressFocusReclaim(_statusFocusNode);
            if (next != null) unawaited(_changeStatus(next));
          },
          items: [
            for (final status in TaskBoard._columns)
              DropdownMenuItem<TaskStatus>(
                value: status,
                child: Text(TaskBoard._columnLabels[status]!),
              ),
          ],
        ),
      ),
    );
  }

  /// Created/Updated, in small muted text at the bottom of the sidebar —
  /// display-only, matching the reference layout's own footer timestamps.
  Widget _buildTimestamps(bool isDark) {
    final mutedColor = isDark ? Colors.white24 : Colors.grey.shade400;
    final format = DateFormat('MMM d, yyyy · HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Created ${format.format(widget.task.createdAt)}',
          style: TextStyle(fontSize: 10.5, color: mutedColor),
        ),
        const SizedBox(height: 2),
        Text(
          'Updated ${format.format(widget.task.updatedAt)}',
          style: TextStyle(fontSize: 10.5, color: mutedColor),
        ),
      ],
    );
  }

  /// The right sidebar column: the things the user SETS and the things
  /// ATTACHED to the task — the status control at the top, the Details
  /// card, the linked-notes section, then the timestamps at the bottom
  /// (reference layout). Linked notes live here rather than in the left
  /// content column: they are references attached to the task, like
  /// Project or Scheduled date, not prose the user writes — and keeping
  /// them out of the left column lets its description editor own the full
  /// remaining height there instead of sharing it.
  ///
  /// No `Expanded`/`Spacer` here, deliberately — this same column is reused
  /// unchanged in both the side-by-side layout (bounded height, inside a
  /// `SingleChildScrollView` within a Row's `Expanded` — see [_buildBody] —
  /// so a long notes list scrolls independently instead of overflowing) and
  /// the stacked layout (unbounded height, inside the body's own
  /// `SingleChildScrollView`), and a `Spacer` would throw under either.
  Widget _buildSidebar(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusControl(isDark),
        const SizedBox(height: 20),
        _sectionHeader('Details', isDark),
        _buildDetailsCard(isDark),
        const SizedBox(height: 20),
        _buildNotesSection(isDark),
        const SizedBox(height: 20),
        _buildTimestamps(isDark),
      ],
    );
  }

  /// The quiet heading strip above the two columns — a close affordance
  /// mirroring the reference layout's header bar. Pops without saving,
  /// same as the footer's Cancel — not a new behavior, just an additional
  /// way to reach the same existing dismissal.
  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Task Details',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          tooltip: 'Close',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          // Routes through the same save-then-close path as the barrier
          // and Escape (see [build]'s `PopScope`) rather than popping
          // directly — one of the three ways this dialog can close, and
          // all three must persist identically.
          onPressed: _closeDialog,
        ),
      ],
    );
  }

  /// The two-column body, or its stacked fallback below
  /// [_stackBreakpointWidth]: the sidebar renders below the content column
  /// instead of squeezing beside it (a `RenderFlex overflow` on a narrow,
  /// resizable desktop window is a real bug, not a test artifact).
  ///
  /// In the side-by-side layout the sidebar is wrapped in its own
  /// `SingleChildScrollView` — with a bounded-height `Expanded` ancestor
  /// (from the Row) and no scroll wrapper, a long linked-notes list plus
  /// the rest of the sidebar's content could exceed the available height
  /// and overflow; scrolling it independently keeps the left column's own
  /// height (and the description editor's `Expanded`) unaffected. The
  /// stacked layout already scrolls both columns together, so it needs no
  /// separate wrapper here.
  Widget _buildBody(bool isDark, {required bool stacked}) {
    if (stacked) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLeftColumn(isDark, stacked: true),
            const SizedBox(height: 28),
            _buildSidebar(isDark),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildLeftColumn(isDark, stacked: false)),
        const SizedBox(width: 28),
        Expanded(
          child: SingleChildScrollView(child: _buildSidebar(isDark)),
        ),
      ],
    );
  }

  /// Comfortable two-column width (reference layout: ~980-1040 logical
  /// px) — the ceiling the dialog grows to on a wide window.
  static const double _dialogMaxWidth = 1000;

  /// Ceiling for the dialog's own height.
  static const double _dialogHeight = 680;

  /// Below this width the sidebar stacks under the content column instead
  /// of squeezing beside it.
  static const double _stackBreakpointWidth = 720;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaSize = MediaQuery.of(context).size;

    // Computed from MediaQuery (not a LayoutBuilder inside the dialog)
    // so the SAME value both sizes the dialog's SizedBox and decides
    // whether to stack — the two can never disagree. 80/96 mirror
    // AlertDialog's own default `insetPadding` (40 horizontal, and a
    // smaller vertical margin here since height already has its own
    // scroll/shrink fallback below).
    final availableWidth = mediaSize.width - 80;
    final dialogWidth = math.max(280.0, math.min(availableWidth, _dialogMaxWidth));
    final availableHeight = mediaSize.height - 96;
    final dialogHeight = math.max(320.0, math.min(availableHeight, _dialogHeight));
    final stacked = dialogWidth < _stackBreakpointWidth;

    return PopScope(
      // Always false: the framework never gets to pop this route on its
      // own. Every dismissal — the barrier tap and Escape both resolve to
      // `Navigator.maybePop` (see `ModalBarrier.onDismiss` and
      // `_DismissModalAction` in the framework's routes.dart), which
      // consults `canPop` and, finding it false, blocks the pop and calls
      // `onPopInvokedWithResult` below with `didPop: false` instead. That
      // is what actually triggers [_closeDialog] for those two paths. The
      // header X (in [_buildHeader]) calls [_closeDialog] directly, whose
      // own `Navigator.pop` is an imperative pop that bypasses `canPop`
      // and reports back here with `didPop: true` — already handled, so
      // it is a no-op. Net effect: three ways to close this dialog, one
      // path (`_closeDialog`) that decides what gets persisted first.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_closeDialog());
      },
      child: AlertDialog(
        // Mirrors `TimeEntryEditor`'s `AlertDialog.backgroundColor` — the
        // app's own dark-neutral surface, not the ambient (seed-tinted)
        // theme default. See [surfaceColor]'s doc for why.
        backgroundColor: Color.alphaBlend(
          widget.surfaceColor.withValues(alpha: 0.96),
          isDark ? Colors.black : Colors.white,
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(isDark),
              const SizedBox(height: 16),
              Expanded(child: _buildBody(isDark, stacked: stacked)),
            ],
          ),
        ),
        // No Save/Cancel footer (settled decision: the reference model —
        // a Jira issue modal — has neither; edits persist on close, see
        // [_closeDialog]). Removing `actions` also reclaims the vertical
        // space `AlertDialog` reserved for that row.
      ),
    );
  }
}

/// The linked-note editor/preview modal opened from the task detail
/// dialog's NOTES section — both "create a note" and "preview a linked
/// note" open here (settled decision: "para crear la nota estaría bien
/// que fuera un modal como ya lo haces, y para el preview también"),
/// layered on top of the task dialog rather than taking over its NOTES
/// section in place, same [showAnimatedDialog] convention every other
/// dialog in this feature follows.
///
/// Reuses [NoteMarkdownEditor] with `initialViewMode: EditorViewMode.preview`
/// — a note WITH content opens RENDERED ("que se vea el md bien, y no en
/// modo código"), while a brand-new EMPTY note downgrades to the plain
/// edit field automatically (see [NoteMarkdownEditor.initialViewMode]'s doc
/// and `note_markdown_editor_test.dart`'s "preview downgrades to edit on
/// an empty note"), so a freshly created note is immediately typable.
/// Editing is never disabled from here — the editor's own edit⇄preview
/// toggle stays available; rendered is the DEFAULT, not a restriction.
///
/// The title is an editable field too (not static text) — a note created
/// from a task defaults to the current date ([CreateNoteUseCase]), so two
/// notes created the same day are otherwise indistinguishable in the NOTES
/// list.
///
/// Both title and content persist through [UpdateNoteUseCase] on a shared
/// short debounce, entirely separate from the task detail dialog's own
/// title/description/blockedReason save-on-close flow, so opening or
/// editing a note here never marks the TASK dirty. Every dismissal (the
/// header close button, barrier tap, Escape) flushes any pending edit
/// first, via the same `PopScope(canPop: false)` pattern
/// [_TaskDetailDialogState.build] itself uses — see that method's doc for
/// why `canPop: false` is required to intercept the barrier/Escape paths
/// rather than letting them pop silently.
///
/// Every dismissal pops with the freshest [Note] (post-flush) alongside a
/// flag for whether "Open in full editor" was requested — the caller
/// ([_TaskDetailDialogState._openNoteEditor]) uses the freshest [Note] to
/// refresh its own `_noteResolutions` cache unconditionally, not only on
/// the full-editor path. Without that refresh, the cache keeps serving the
/// PRE-edit [Note] on the next open, which reads to the user exactly like
/// their edit was never saved (it was — see this class's own persistence
/// doc above; that failure mode is a stale in-memory read, not data loss).
class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({
    required this.note,
    required this.accentColor,
    required this.surfaceColor,
  });

  final Note note;
  final Color accentColor;

  /// Same fixed dark-neutral surface as the task detail dialog this one
  /// opens from — see [_TaskDetailDialog.surfaceColor]'s doc for why it is
  /// threaded explicitly rather than left to `AlertDialog`'s own
  /// `ColorScheme.fromSeed`-derived default.
  final Color surfaceColor;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late Note _note;
  late String _content;
  late String _title;
  late String? _projectId;
  late final TextEditingController _titleController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _content = widget.note.content;
    _title = widget.note.title;
    _projectId = widget.note.projectId;
    _titleController = TextEditingController(text: _title);
  }

  @override
  void dispose() {
    // Belt-and-suspenders only — every real dismissal path ([_close],
    // [_openFullEditor]) already flushes before the pop that eventually
    // leads here.
    _debounce?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  /// Marks the content dirty and (re)starts the shared debounce — mirrors
  /// the shape of `AutoSaveService.markDirty`/`_tick`, but scoped locally
  /// to this modal and this one note, deliberately NOT the global
  /// `AppState.autoSaveService` singleton (that instance is owned by the
  /// full note editor page's own watch/flush lifecycle; sharing it here
  /// would mean this modal and the editor page fight over its single
  /// watched-note slot).
  void _onChanged(String value) {
    _content = value;
    _scheduleFlush();
  }

  /// Same contract as [_onChanged], for the title field — a shared
  /// debounce means typing a title then immediately typing content (or
  /// vice versa) still flushes both together in one write.
  void _onTitleChanged(String value) {
    _title = value;
    _scheduleFlush();
  }

  /// Folder (NoteProject) selector callback — settled decision: "que cuando
  /// crees la nota puedas decir dónde guardar", put IN the modal rather
  /// than a separate pre-create step, so it doubles as a way to MOVE an
  /// existing note between folders later, not only at creation. Same
  /// debounced-flush path as title/content (never a direct write) — see
  /// [_flush]'s doc for why [_projectId] is always passed as a concrete
  /// value, never the `_Unset` sentinel itself.
  void _onFolderChanged(String? value) {
    setState(() => _projectId = value);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_flush()),
    );
  }

  /// Persists [_title], [_content] and [_projectId] through
  /// [UpdateNoteUseCase] directly — entirely separate from the task detail
  /// dialog's own title/description/blockedReason save-on-close flow, so an
  /// edit here never marks the TASK dirty or touches its `updatedAt`. A
  /// no-op write (nothing actually changed) is skipped by
  /// [UpdateNoteUseCase] itself. Safe to call with nothing pending — every
  /// dismissal path calls this unconditionally. Deliberately never
  /// reassigns [_titleController]'s text after a flush — doing so would
  /// reseed the field mid-edit, the same class of bug
  /// [NoteMarkdownEditor]'s id-only `ValueKey` already guards against for
  /// content.
  ///
  /// [_projectId] is always passed as a concrete `String?` (the chosen
  /// folder id, or `null` for root) — never [UpdateNoteUseCase]'s own
  /// private `_Unset` sentinel, which is not even visible outside that
  /// file. Passing a concrete value is how [AppState.updateNoteProject]
  /// (the other real caller of this parameter) resolves the same sentinel
  /// safely; the trap this codebase has hit before is forwarding a
  /// DIFFERENT file's `_Unset` instance into this one's `is _Unset` check,
  /// which falls through to a throwing cast.
  Future<void> _flush() async {
    _debounce?.cancel();
    _debounce = null;
    if (_content == _note.content &&
        _title == _note.title &&
        _projectId == _note.projectId) {
      return;
    }
    final updated = await GetIt.instance<UpdateNoteUseCase>().execute(
      noteId: _note.id,
      title: _title,
      content: _content,
      projectId: _projectId,
    );
    if (updated == null) return;
    _note = updated;
    if (mounted) setState(() {});
  }

  Future<void> _close() async {
    await _flush();
    if (mounted) Navigator.of(context).pop((_note, false));
  }

  Future<void> _openFullEditor() async {
    await _flush();
    if (mounted) Navigator.of(context).pop((_note, true));
  }

  /// Folder (NoteProject) selector — "No folder" plus every folder
  /// [AppState] knows about (settled decision: "si tienes carpetas te
  /// aparezcan ahí"), same shape as [_TaskDetailDialogState]'s own project
  /// selector for tasks. Selecting a folder never persists directly — see
  /// [_onFolderChanged]'s doc for why it goes through the shared debounced
  /// flush instead.
  ///
  /// Rebalanced header (settled decision: "no se ve proporcional") — Title
  /// and Folder are peer metadata about the note, both edited before
  /// writing starts, so this now shares the EXACT same outlined/labelled
  /// `InputDecoration` recipe as the Title field beside it (radius 12,
  /// accent-coloured `focusedBorder`) instead of being bare text with no
  /// container. Do not invent a third input style — see the Title field's
  /// own decoration doc.
  ///
  /// If [_projectId] points at a folder [AppState.noteProjects] doesn't
  /// carry (soft-deleted), a synthetic "Deleted folder" entry keeps the
  /// dropdown's selected value valid — same degrade-the-display-keep-the-
  /// data rule [_TaskDetailDialogState._buildProjectSelector] already
  /// applies for a task's project.
  Widget _buildFolderSelector(bool isDark) {
    final appState = GetIt.instance<AppState>();
    final folders = appState.noteProjects;
    final isDangling =
        _projectId != null && appState.noteProjectForId(_projectId) == null;
    final mutedColor = isDark ? Colors.white54 : Colors.grey.shade600;

    return DropdownButtonFormField<String?>(
      key: const Key('task-note-folder-selector'),
      // `initialValue`, not the deprecated `value` — safe here because
      // this widget carries a fixed `Key`, so Flutter reuses the same
      // `FormFieldState` across this dialog's rebuilds, and the only
      // mutator of [_projectId] is this dropdown's own `onChanged`
      // ([_onFolderChanged]); nothing external ever needs to push a new
      // selected value into an already-built instance.
      initialValue: _projectId,
      isDense: true,
      isExpanded: true,
      icon: Icon(Icons.expand_more_rounded, size: 18, color: mutedColor),
      style: TextStyle(fontSize: 12.5, color: mutedColor),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Folder',
        prefixIcon: Icon(Icons.folder_outlined, size: 15, color: mutedColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.accentColor, width: 2),
        ),
      ),
      onChanged: _onFolderChanged,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('No folder', overflow: TextOverflow.ellipsis),
        ),
        if (isDangling)
          DropdownMenuItem<String?>(
            value: _projectId,
            child:
                const Text('Deleted folder', overflow: TextOverflow.ellipsis),
          ),
        for (final folder in folders)
          DropdownMenuItem<String?>(
            value: folder.id,
            child: Text(folder.name, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final mediaSize = MediaQuery.of(context).size;
    // Comfortable, bounded writing-surface size — same "clamp to the
    // available space" shape as [_TaskDetailDialogState.build]'s own
    // dialog sizing, scaled down for a single-note modal rather than the
    // two-column task dialog.
    final width = math.max(320.0, math.min(mediaSize.width - 120, 640.0));
    final height = math.max(320.0, math.min(mediaSize.height - 160, 560.0));

    return PopScope(
      // Same contract as the task detail dialog's own PopScope — see
      // [_TaskDetailDialogState.build]'s doc for why `canPop: false` is
      // required so the barrier tap and Escape both funnel through
      // [_close] instead of popping (and skipping the flush) directly.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        unawaited(_close());
      },
      child: AlertDialog(
        // Same theme fix as the parent task detail dialog — see
        // [_TaskDetailDialog.surfaceColor]'s doc.
        backgroundColor: Color.alphaBlend(
          widget.surfaceColor.withValues(alpha: 0.96),
          isDark ? Colors.black : Colors.white,
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title and Folder are peers (both metadata about the note,
              // edited before writing starts) sharing one row and one
              // decoration recipe — settled decision: "no se ve
              // proporcional", fixed by giving them matching visual weight
              // instead of a tall bordered title next to bare folder text.
              // The action icons stay on this same row, vertically centred
              // by the Row's default `CrossAxisAlignment.center` against
              // the Title/Folder controls, and are muted rather than
              // accent-coloured so they read as secondary and never
              // compete with the Title field for weight.
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('task-note-title-field'),
                      controller: _titleController,
                      onChanged: _onTitleChanged,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: mutedColor,
                      ),
                      // Same outlined/labelled treatment as every other
                      // input in this feature (task dialog Title, New Task
                      // Title, blocked-reason field) — settled decision:
                      // "no se parece a los otros inputs que tenemos".
                      // The New Task dialog's Title field is the one
                      // other input that also sets an accent-coloured
                      // `focusedBorder`, so this matches THAT shape rather
                      // than the plain (no focusedBorder) task-detail
                      // Title field — do not invent a third style. The
                      // Folder selector beside it (`_buildFolderSelector`)
                      // now shares this exact decoration so the two read
                      // as one control group.
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Title',
                        hintText: 'Untitled',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: widget.accentColor, width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 150,
                    child: _buildFolderSelector(isDark),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: mutedColor,
                    ),
                    tooltip: 'Open in full editor',
                    splashRadius: 16,
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => unawaited(_openFullEditor()),
                  ),
                  IconButton(
                    icon:
                        Icon(Icons.close_rounded, size: 20, color: mutedColor),
                    tooltip: 'Close note',
                    splashRadius: 16,
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => unawaited(_close()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  key: const Key('task-note-preview'),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: NoteMarkdownEditor(
                    // Keyed by note id only (not content) so a debounced
                    // flush's own `setState` never reseeds the editor's
                    // internal controller mid-edit — same contract the old
                    // in-place preview editor relied on.
                    key: ValueKey('task-note-editor-${_note.id}'),
                    initialContent: _note.content,
                    initialViewMode: EditorViewMode.preview,
                    toolbar: EditorToolbarProfile.minimal,
                    onChanged: _onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "New Project" dialog opened from the task detail dialog's project
/// selector (settled decision: "en project que se puedan crear proyectos
/// desde ahí también") — same fields and shared [kProjectColors] palette as
/// `timer_page.dart`'s own "New Project" dialog. Goes through
/// [TimerState.createProject] (wrapping `CreateProjectUseCase`), never a
/// direct write. An empty/whitespace name does nothing rather than
/// creating a blank project; Cancel does nothing.
///
/// A dedicated `StatefulWidget` — not a `TextEditingController` owned by
/// the caller's async method — deliberately: [showAnimatedDialog]'s
/// returned Future resolves as soon as `Navigator.pop` is called, roughly
/// 250ms before its exit transition finishes removing this widget from
/// the tree. A controller disposed by the CALLER immediately after that
/// Future resolves would still be attached to a TextField that keeps
/// rebuilding during the exit animation, throwing "used after being
/// disposed". Owning the controller here ties its disposal to this
/// widget's own [dispose], which the framework only calls once the exit
/// animation actually finishes and the route is removed.
class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog({
    required this.accentColor,
    required this.surfaceColor,
  });

  final Color accentColor;

  /// Same fixed dark-neutral surface as the task detail dialog this one
  /// opens from — see [_TaskDetailDialog.surfaceColor]'s doc for why it is
  /// threaded explicitly rather than left to `AlertDialog`'s own
  /// `ColorScheme.fromSeed`-derived default.
  final Color surfaceColor;

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final TextEditingController _nameController = TextEditingController();
  int _selectedColorValue = kProjectColors.first.toARGB32();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final project = await GetIt.instance<TimerState>().createProject(
      name: name,
      colorValue: _selectedColorValue,
    );
    if (mounted) Navigator.pop(context, project.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      // Same theme fix as the parent task detail dialog — see
      // [_TaskDetailDialog.surfaceColor]'s doc.
      backgroundColor: Color.alphaBlend(
        widget.surfaceColor.withValues(alpha: 0.96),
        isDark ? Colors.black : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'New Project',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Project name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Color',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kProjectColors.map((c) {
              final isSelected = c.toARGB32() == _selectedColorValue;
              return GestureDetector(
                onTap: () => setState(() => _selectedColorValue = c.toARGB32()),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: c.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _create,
          style: FilledButton.styleFrom(
            backgroundColor: widget.accentColor,
            // Same fix as the parent dialog's own accent-coloured
            // buttons: left to the ambient theme, the label resolves
            // against `colorScheme.onPrimary` (the SEED's tonal primary),
            // not the literal accentColor used as the background.
            foregroundColor: widget.accentColor.computeLuminance() > 0.5
                ? Colors.black
                : Colors.white,
          ),
          child: const Text('Create'),
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
  const _NotePickerDialog({
    required this.notes,
    required this.accentColor,
    required this.surfaceColor,
  });

  final List<Note> notes;
  final Color accentColor;

  /// Same fixed dark-neutral surface as the task detail dialog this one
  /// opens from — see [_TaskDetailDialog.surfaceColor]'s doc for why it is
  /// threaded explicitly rather than left to `AlertDialog`'s own
  /// `ColorScheme.fromSeed`-derived default.
  final Color surfaceColor;

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
      // Same theme fix as the parent task detail dialog — see
      // [_TaskDetailDialog.surfaceColor]'s doc.
      backgroundColor: Color.alphaBlend(
        widget.surfaceColor.withValues(alpha: 0.96),
        isDark ? Colors.black : Colors.white,
      ),
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
