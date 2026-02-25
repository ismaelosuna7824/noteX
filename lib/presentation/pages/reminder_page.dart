import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../domain/entities/reminder.dart';
import '../state/app_state.dart';
import '../state/reminder_state.dart';
import '../state/theme_state.dart';

/// Dark-mode card surface — same as other pages for visual consistency.
const _kDarkCard = Color(0xFF1A1A2E);

/// Full CRUD page for managing reminders.
class ReminderPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const ReminderPage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final _reminderState = GetIt.instance<ReminderState>();

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _reminderState.initialize();
  }

  Future<void> _showAddReminderDialog(BuildContext context) async {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    final accentColor = widget.themeState.accentColor;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'New Reminder',
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
                      hintText: 'What do you need to remember?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: accentColor, width: 2),
                      ),
                    ),
                    onSubmitted: (_) {
                      if (titleController.text.trim().isNotEmpty) {
                        _reminderState.createReminder(
                          title: titleController.text.trim(),
                          scheduledDate: selectedDate,
                        );
                        Navigator.of(ctx).pop();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030, 12, 31),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme:
                                  Theme.of(context).colorScheme.copyWith(
                                        primary: accentColor,
                                      ),
                            ),
                            child: child!,
                          );
                        },
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
                            '${_monthNames[selectedDate.month - 1]} ${selectedDate.day}, ${selectedDate.year}',
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
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (titleController.text.trim().isNotEmpty) {
                    _reminderState.createReminder(
                      title: titleController.text.trim(),
                      scheduledDate: selectedDate,
                    );
                    Navigator.of(ctx).pop();
                  }
                },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = widget.themeState.accentColor;

    final cardColor = isDark
        ? _kDarkCard.withValues(alpha: 0.90)
        : Colors.white.withValues(alpha: 0.95);
    final cardBorder =
        isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200;
    final cardShadow = Colors.black.withValues(alpha: isDark ? 0.30 : 0.04);
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.10) : Colors.grey.shade200;

    return ListenableBuilder(
      listenable: _reminderState,
      builder: (context, _) {
        final reminders = _reminderState.reminders;
        final pending =
            reminders.where((r) => !r.isCompleted).toList();
        final completed =
            reminders.where((r) => r.isCompleted).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cardBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: cardShadow,
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.notifications_rounded,
                      size: 22,
                      color: accentColor,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Reminders',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _showAddReminderDialog(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Reminder'),
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Divider(color: dividerColor),
                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: reminders.isEmpty
                      ? _buildEmptyState(isDark, accentColor)
                      : ListView(
                          children: [
                            if (pending.isNotEmpty) ...[
                              _buildSectionHeader(
                                'Pending',
                                pending.length,
                                accentColor,
                                isDark,
                              ),
                              const SizedBox(height: 8),
                              ...pending.map((r) => _buildReminderTile(
                                    r,
                                    isDark,
                                    accentColor,
                                  )),
                            ],
                            if (completed.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildSectionHeader(
                                'Completed',
                                completed.length,
                                Colors.green,
                                isDark,
                              ),
                              const SizedBox(height: 8),
                              ...completed.map((r) => _buildReminderTile(
                                    r,
                                    isDark,
                                    accentColor,
                                  )),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark, Color accentColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 48,
            color: isDark
                ? Colors.white.withValues(alpha: 0.20)
                : Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            'No reminders yet',
            style: TextStyle(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.40)
                  : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showAddReminderDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create Reminder'),
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String label,
    int count,
    Color color,
    bool isDark,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReminderTile(
    Reminder reminder,
    bool isDark,
    Color accentColor,
  ) {
    return _ReminderTile(
      reminder: reminder,
      isDark: isDark,
      accentColor: accentColor,
      onComplete: () => _reminderState.completeReminder(reminder.id),
      onDelete: () => _reminderState.deleteReminder(reminder.id),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminder tile with hover animation (lift + accent border glow).
// ─────────────────────────────────────────────────────────────────────────────

class _ReminderTile extends StatefulWidget {
  final Reminder reminder;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _ReminderTile({
    required this.reminder,
    required this.isDark,
    required this.accentColor,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile> {
  bool _hovered = false;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final reminder = widget.reminder;
    final isDark = widget.isDark;
    final accentColor = widget.accentColor;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final scheduled = DateTime(
      reminder.scheduledDate.year,
      reminder.scheduledDate.month,
      reminder.scheduledDate.day,
    );
    final isOverdue = !reminder.isCompleted && scheduled.isBefore(today);
    final isToday = scheduled.isAtSameMomentAs(today);

    final itemBg = isDark
        ? Colors.white.withValues(alpha: _hovered ? 0.10 : 0.07)
        : (_hovered ? Colors.grey.shade100 : Colors.grey.shade50);
    final itemBorder = _hovered
        ? accentColor.withValues(alpha: 0.25)
        : (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.grey.shade200);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: itemBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: itemBorder, width: 1),
          ),
          child: Row(
            children: [
              // Checkbox
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: reminder.isCompleted,
                  onChanged: reminder.isCompleted
                      ? null
                      : (_) => widget.onComplete(),
                  activeColor: accentColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title
              Expanded(
                child: Text(
                  reminder.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: reminder.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: reminder.isCompleted
                        ? (isDark ? Colors.white38 : Colors.grey.shade400)
                        : null,
                  ),
                ),
              ),

              // Date badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? Colors.red.withValues(alpha: 0.12)
                      : isToday
                          ? accentColor.withValues(alpha: 0.12)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isToday
                      ? 'Today'
                      : '${_monthNames[reminder.scheduledDate.month - 1]} ${reminder.scheduledDate.day}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isOverdue
                        ? Colors.red
                        : isToday
                            ? accentColor
                            : (isDark
                                ? Colors.white54
                                : Colors.grey.shade600),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Delete button
              IconButton(
                onPressed: widget.onDelete,
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                ),
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
