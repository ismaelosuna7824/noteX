import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../application/use_cases/task/resolve_task_note_link_use_case.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/task.dart';
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
  });

  final TaskState taskState;
  final ThemeState themeState;

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
    required this.isDark,
    this.onCreate,
  });

  final TaskStatus status;
  final String label;
  final List<Task> tasks;
  final TaskState taskState;
  final ThemeState themeState;
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

// ─────────────────────────────────────────────────────────────────────────
// Board card: draggable, opens the detail dialog on tap.
// ─────────────────────────────────────────────────────────────────────────

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.task,
    required this.taskState,
    required this.themeState,
    required this.isDark,
  });

  final Task task;
  final TaskState taskState;
  final ThemeState themeState;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final card = _CardBody(task: task, themeState: themeState, isDark: isDark);
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
          onTap: () => showDialog<void>(
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
    required this.isDark,
  });

  final Task task;
  final ThemeState themeState;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accentColor = themeState.accentColor;
    final date = task.scheduledDate;
    final isDone = task.status == TaskStatus.done;
    final hasReason =
        task.status == TaskStatus.blocked && (task.blockedReason?.trim().isNotEmpty ?? false);

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

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _blockedReasonController =
        TextEditingController(text: widget.task.blockedReason ?? '');
    _description = widget.task.description;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _blockedReasonController.dispose();
    super.dispose();
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

  /// Starts a timer linked to this task (design D1's own scenario: "the
  /// user starts the timer from the board and watches the card"). The task
  /// write is best-effort — a failure never blocks the timer, and is
  /// surfaced here as a non-blocking SnackBar rather than swallowed.
  Future<void> _startTimer() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await GetIt.instance<TimerState>().startTimer(
      taskId: widget.task.id,
      description: widget.task.title,
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
    navigator.pop();
  }

  /// Opens the note picker and links the chosen note to this task
  /// (`UpdateTaskUseCase` via [TaskState.updateTask] — title/status
  /// untouched, no status quartet emitted). This is the missing half of
  /// note-linking: the three affordance states in [_openLinkedNote] could
  /// only ever unlink or resolve an existing link — nothing in the UI
  /// could set `noteId` to a real value until this.
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
    await widget.taskState.updateTask(widget.task.id, noteId: selected.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// Resolves and opens `widget.task.noteId` through the three affordance
  /// states (design D9): found and live → navigate to it; found and
  /// soft-deleted → offer to restore, then open; not found → offer to
  /// clear the link. Always via [ResolveTaskNoteLinkUseCase], never the
  /// deletedAt-filtered in-memory note list.
  Future<void> _openLinkedNote() async {
    final noteId = widget.task.noteId;
    if (noteId == null) return;

    final resolution =
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
        final clear = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Note not found'),
            content: const Text('The linked note no longer exists.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Clear link'),
              ),
            ],
          ),
        );
        if (clear == true && mounted) {
          await widget.taskState.updateTask(widget.task.id, noteId: null);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBlocked = widget.task.status == TaskStatus.blocked;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: TextField(
        controller: _titleController,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
      ),
      content: SizedBox(
        width: 480,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.task.noteId != null) ...[
              OutlinedButton.icon(
                onPressed: _openLinkedNote,
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Open linked note'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.accentColor,
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _linkNote,
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Link note'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.accentColor,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (isBlocked) ...[
              TextField(
                controller: _blockedReasonController,
                decoration: const InputDecoration(
                  labelText: 'Blocked reason',
                  hintText: 'What is this waiting on?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
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
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton.icon(
          onPressed: _startTimer,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Start timer'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _save,
              style:
                  FilledButton.styleFrom(backgroundColor: widget.accentColor),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
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
