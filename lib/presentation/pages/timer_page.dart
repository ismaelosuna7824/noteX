import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/project.dart';
import '../../domain/entities/time_entry.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../state/timer_state.dart';
import '../widgets/glassmorphic_container.dart';
import 'package:get_it/get_it.dart';
import '../widgets/animated_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Preset colors for new projects
// ─────────────────────────────────────────────────────────────────────────────
const _projectColors = [
  Color(0xFF6C5CE7), // Purple
  Color(0xFF0984E3), // Blue
  Color(0xFF00B894), // Teal
  Color(0xFFE17055), // Coral
  Color(0xFFF5A623), // Amber
  Color(0xFFE84393), // Pink
  Color(0xFF2D3436), // Dark
  Color(0xFF00CEC9), // Cyan
  Color(0xFFD63031), // Red
  Color(0xFF6AB04C), // Green
];

// ─────────────────────────────────────────────────────────────────────────────
// Timer Page
// ─────────────────────────────────────────────────────────────────────────────

class TimerPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const TimerPage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  late final TimerState _timerState;
  final TextEditingController _descController = TextEditingController();

  /// null = show all projects; '__none__' = no project; else project id.
  String? _filterProjectId;

  /// Tracks whether the timer was running so we can clear after stop.
  bool _wasRunning = false;

  @override
  void initState() {
    super.initState();
    _timerState = GetIt.instance<TimerState>();
    _timerState.initialize();
    _timerState.addListener(_onTimerChanged);
  }

  void _onTimerChanged() {
    if (_timerState.isRunning) {
      // Timer just started → clear the input so it shows "Running…" hint.
      if (!_wasRunning) {
        _wasRunning = true;
        _descController.clear();
      }
    } else {
      // Timer just stopped → clear description only.
      // Keep _filterProjectId and project chip so the next entry
      // defaults to the same project automatically.
      if (_wasRunning) {
        _wasRunning = false;
        _descController.clear();
        _timerState.setDraftDescription('');
      }
    }
  }

  @override
  void dispose() {
    _timerState.removeListener(_onTimerChanged);
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _timerState,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              // ── Timer bar ─────────────────────────────────────────────────
              _TimerBar(
                timerState: _timerState,
                themeState: widget.themeState,
                descController: _descController,
                onProjectSelected: (id) =>
                    setState(() => _filterProjectId = id),
              ),
              const SizedBox(height: 10),

              // ── Week nav bar ──────────────────────────────────────────────
              _WeekNavBar(
                timerState: _timerState,
                themeState: widget.themeState,
              ),
              const SizedBox(height: 10),

              // ── Entries list ──────────────────────────────────────────────
              Expanded(
                child: _timerState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _EntriesList(
                        timerState: _timerState,
                        themeState: widget.themeState,
                        filterProjectId: _filterProjectId,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timer Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TimerBar extends StatelessWidget {
  final TimerState timerState;
  final ThemeState themeState;
  final TextEditingController descController;
  final ValueChanged<String?> onProjectSelected;

  const _TimerBar({
    required this.timerState,
    required this.themeState,
    required this.descController,
    required this.onProjectSelected,
  });

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accentColor;
    final isRunning = timerState.isRunning;

    return GlassmorphicContainer(
      borderRadius: 18,
      opacity: Theme.of(context).brightness == Brightness.dark ? 0.90 : 0.92,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Description field
          Expanded(
            child: TextField(
              controller: descController,
              onChanged: isRunning ? null : timerState.setDraftDescription,
              onSubmitted: isRunning
                  ? null
                  : (_) {
                      timerState.setDraftDescription(descController.text);
                      timerState.startTimer();
                    },
              textInputAction: TextInputAction.go,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.grey.shade800,
              ),
              decoration: InputDecoration(
                hintText: isRunning
                    ? 'Running…'
                    : 'What are you working on?  ↵',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintStyle: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white38
                      : Colors.grey.shade400,
                  fontWeight: FontWeight.w400,
                ),
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              readOnly: isRunning,
            ),
          ),
          const SizedBox(width: 12),

          // Project chip
          _ProjectChip(
            timerState: timerState,
            themeState: themeState,
            enabled: !isRunning,
            onProjectSelected: onProjectSelected,
          ),
          const SizedBox(width: 16),

          // Elapsed time
          Text(
            _formatDuration(timerState.liveElapsed),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: isRunning ? accent : Colors.grey.shade400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 16),

          // Play / Stop button
          GestureDetector(
            onTap: isRunning
                ? () => timerState.stopTimer()
                : () {
                    timerState.setDraftDescription(descController.text);
                    timerState.startTimer();
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isRunning ? accent : accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Project Chip
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectChip extends StatelessWidget {
  final TimerState timerState;
  final ThemeState themeState;
  final bool enabled;
  final ValueChanged<String?> onProjectSelected;

  const _ProjectChip({
    required this.timerState,
    required this.themeState,
    required this.enabled,
    required this.onProjectSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selectedId = timerState.isRunning
        ? timerState.runningEntry?.projectId
        : timerState.draftProjectId;
    final project = timerState.projectForId(selectedId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: enabled ? () => _showProjectMenu(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: project != null
              ? project.color.withValues(alpha: 0.15)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: project != null
                ? project.color.withValues(alpha: 0.4)
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (project != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: project.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                project.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: project.color,
                ),
              ),
            ] else ...[
              Icon(
                Icons.folder_outlined,
                size: 14,
                color: isDark ? Colors.white54 : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                'No Project',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                ),
              ),
            ],
            if (enabled) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showProjectMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final projects = timerState.projects;
    final currentDraftId = timerState.draftProjectId;

    Widget checkIfActive(String? id) => SizedBox(
          width: 18,
          child: currentDraftId == id
              ? Icon(Icons.check_rounded,
                  size: 14, color: themeState.accentColor)
              : null,
        );

    final result = await showMenu<String?>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        // No Project option (also acts as "clear filter")
        PopupMenuItem<String?>(
          value: '__none__',
          child: Row(
            children: [
              checkIfActive(null),
              const SizedBox(width: 4),
              Icon(Icons.folder_outlined, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text('No Project',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
        ),
        if (projects.isNotEmpty)
          const PopupMenuDivider(),
        ...projects.map(
          (p) => PopupMenuItem<String?>(
            value: p.id,
            child: Row(
              children: [
                checkIfActive(p.id),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: p.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(p.name, style: const TextStyle(fontSize: 13)),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context); // close menu first
                    _showDeleteProjectDialog(context, p);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline_rounded,
                        size: 15, color: Colors.red.shade300),
                  ),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        // New project
        PopupMenuItem<String?>(
          value: '__new__',
          child: Row(
            children: [
              const SizedBox(width: 22), // align with others
              Icon(Icons.add_rounded, size: 16, color: themeState.accentColor),
              const SizedBox(width: 8),
              Text('New Project',
                  style: TextStyle(
                    color: themeState.accentColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  )),
            ],
          ),
        ),
      ],
    );

    if (result == null) return;
    if (result == '__new__' && context.mounted) {
      await _showNewProjectDialog(context);
      // After creation, timerState.draftProjectId holds the new project id.
      // Propagate to filter.
      onProjectSelected(timerState.draftProjectId);
    } else if (result == '__none__') {
      timerState.setDraftProject(null);
      onProjectSelected('__none__'); // filter to show only no-project entries
    } else {
      timerState.setDraftProject(result);
      onProjectSelected(result); // filter entries by this project
    }
  }

  Future<void> _showNewProjectDialog(BuildContext context) async {
    final nameController = TextEditingController();
    int selectedColorValue = _projectColors.first.toARGB32();

    await showAnimatedDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('New Project',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
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
              const Text('Color',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _projectColors.map((c) {
                  final isSelected = c.toARGB32() == selectedColorValue;
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedColorValue = c.toARGB32()),
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
                                    blurRadius: 6)
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final project = await timerState.createProject(
                  name: name,
                  colorValue: selectedColorValue,
                );
                timerState.setDraftProject(project.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
  }

  void _showDeleteProjectDialog(BuildContext context, Project project) {
    final entryCount = timerState.weekEntries
        .where((e) => e.projectId == project.id)
        .length;

    showAnimatedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${project.name}"?'),
        content: Text(
          'This will permanently delete the project and all '
          '$entryCount time entr${entryCount == 1 ? 'y' : 'ies'} inside it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await timerState.deleteProject(project.id);
              onProjectSelected(null); // reset filter to All
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Week Nav Bar
// ─────────────────────────────────────────────────────────────────────────────

class _WeekNavBar extends StatelessWidget {
  final TimerState timerState;
  final ThemeState themeState;

  const _WeekNavBar({required this.timerState, required this.themeState});

  @override
  Widget build(BuildContext context) {
    final accent = themeState.accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = timerState.isCurrentWeek
        ? 'This week · W${timerState.weekNumber}'
        : _weekRangeLabel(timerState.weekStart);

    return GlassmorphicContainer(
      borderRadius: 14,
      opacity: isDark ? 0.90 : 0.92,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Previous week
          InkWell(
            onTap: timerState.goToPreviousWeek,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.chevron_left_rounded,
                  color: isDark ? Colors.white70 : Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 8),

          // Week label → opens calendar picker
          GestureDetector(
            onTap: () => _showWeekPicker(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 13,
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),
          // Next week
          InkWell(
            onTap: timerState.goToNextWeek,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.chevron_right_rounded,
                  color: isDark ? Colors.white70 : Colors.grey.shade600),
            ),
          ),

          const Spacer(),

          // Week total
          Text(
            'WEEK TOTAL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.grey.shade400,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(timerState.weekTotal),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _weekRangeLabel(DateTime monday) {
    final sunday = monday.add(const Duration(days: 6));
    return '${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(sunday)}';
  }

  Future<void> _showWeekPicker(BuildContext context) async {
    final selected = await showAnimatedDialog<DateTime>(
      context: context,
      barrierColor: Colors.black38,
      builder: (ctx) => _WeekPickerDialog(
        currentWeekStart: timerState.weekStart,
        accentColor: themeState.accentColor,
      ),
    );
    if (selected != null) {
      await timerState.goToWeek(selected);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Week Picker Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _WeekPickerDialog extends StatefulWidget {
  final DateTime currentWeekStart;
  final Color accentColor;

  const _WeekPickerDialog({
    required this.currentWeekStart,
    required this.accentColor,
  });

  @override
  State<_WeekPickerDialog> createState() => _WeekPickerDialogState();
}

class _WeekPickerDialogState extends State<_WeekPickerDialog> {
  late DateTime _displayMonth;
  late DateTime _selectedWeekStart;

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = widget.currentWeekStart;
    _displayMonth = DateTime(
        widget.currentWeekStart.year, widget.currentWeekStart.month);
  }

  static DateTime _isoMonday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  static int _weekNumber(DateTime monday) {
    final jan4 = DateTime(monday.year, 1, 4);
    final startOfW1 = jan4.subtract(Duration(days: jan4.weekday - 1));
    return ((monday.difference(startOfW1).inDays) / 7).floor() + 1;
  }

  void _navigate(DateTime monday) => Navigator.pop(context, monday);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accentColor;
    final bg = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: SizedBox(
        width: 560,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildShortcutsPanel(isDark, accent),
              VerticalDivider(
                  width: 1,
                  color: isDark ? Colors.white12 : Colors.grey.shade200),
              Expanded(child: _buildCalendarPanel(isDark, accent)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Left panel ─────────────────────────────────────────────────────────────

  Widget _buildShortcutsPanel(bool isDark, Color accent) {
    final now = DateTime.now();
    final thisWeek = _isoMonday(now);
    final lastWeek = thisWeek.subtract(const Duration(days: 7));
    final yesterdayWeek = _isoMonday(now.subtract(const Duration(days: 1)));

    final shortcuts = <(String, DateTime)>[
      ('Today', thisWeek),
      ('Yesterday', yesterdayWeek),
      ('This week', thisWeek),
      ('Last week', lastWeek),
    ];

    return SizedBox(
      width: 148,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'QUICK SELECT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                ),
              ),
            ),
            ...shortcuts.map((s) {
              final isHighlighted = _selectedWeekStart.isAtSameMomentAs(s.$2);
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: InkWell(
                  onTap: () => _navigate(s.$2),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isHighlighted
                          ? accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      s.$1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isHighlighted
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isHighlighted
                            ? accent
                            : (isDark
                                ? Colors.white70
                                : Colors.grey.shade700),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Right panel ────────────────────────────────────────────────────────────

  Widget _buildCalendarPanel(bool isDark, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month navigation header
          Row(
            children: [
              _NavBtn(
                icon: Icons.chevron_left_rounded,
                isDark: isDark,
                onTap: () => setState(() {
                  _displayMonth = DateTime(
                      _displayMonth.year, _displayMonth.month - 1);
                }),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_displayMonth),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.grey.shade800,
                    ),
                  ),
                ),
              ),
              _NavBtn(
                icon: Icons.chevron_right_rounded,
                isDark: isDark,
                onTap: () => setState(() {
                  _displayMonth = DateTime(
                      _displayMonth.year, _displayMonth.month + 1);
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Day-of-week header
          Row(
            children: [
              const SizedBox(width: 36), // week-number column
              ...['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Colors.white38 : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Week rows
          ..._buildWeekRows(isDark, accent),
        ],
      ),
    );
  }

  List<Widget> _buildWeekRows(bool isDark, Color accent) {
    final firstOfMonth =
        DateTime(_displayMonth.year, _displayMonth.month, 1);
    DateTime monday =
        firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));
    final lastOfMonth =
        DateTime(_displayMonth.year, _displayMonth.month + 1, 0);
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    final rows = <Widget>[];
    for (var i = 0; i < 6; i++) {
      if (monday.isAfter(lastOfMonth) &&
          monday.month != _displayMonth.month) { break; }
      rows.add(_buildWeekRow(monday, isDark, accent, todayMidnight));
      monday = monday.add(const Duration(days: 7));
    }
    return rows;
  }

  Widget _buildWeekRow(
      DateTime monday, bool isDark, Color accent, DateTime todayMidnight) {
    final isSelected = monday.isAtSameMomentAs(_selectedWeekStart);
    final weekNum = _weekNumber(monday);

    return GestureDetector(
      onTap: () {
        setState(() => _selectedWeekStart = monday);
        _navigate(monday);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.13) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Week number
            SizedBox(
              width: 36,
              child: Center(
                child: Text(
                  'W$weekNum',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? accent
                        : (isDark ? Colors.white24 : Colors.grey.shade300),
                  ),
                ),
              ),
            ),
            // 7 day cells
            ...List.generate(7, (i) {
              final day = monday.add(Duration(days: i));
              final isCurrentMonth = day.month == _displayMonth.month;
              final isToday = day.isAtSameMomentAs(todayMidnight);

              return Expanded(
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: isToday
                        ? BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isToday
                              ? FontWeight.w800
                              : (isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400),
                          color: isToday
                              ? Colors.white
                              : isCurrentMonth
                                  ? (isDark
                                      ? Colors.white
                                      : Colors.grey.shade800)
                                  : (isDark
                                      ? Colors.white24
                                      : Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// Small arrow button used inside the calendar header
class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _NavBtn(
      {required this.icon, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon,
            size: 20,
            color: isDark ? Colors.white70 : Colors.grey.shade600),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entries List
// ─────────────────────────────────────────────────────────────────────────────

class _EntriesList extends StatefulWidget {
  final TimerState timerState;
  final ThemeState themeState;
  final String? filterProjectId;

  const _EntriesList({
    required this.timerState,
    required this.themeState,
    this.filterProjectId,
  });

  @override
  State<_EntriesList> createState() => _EntriesListState();
}

class _EntriesListState extends State<_EntriesList> {
  /// Persistent controller so the platform scrollbar always has a valid
  /// scroll position even when the list rebuilds every second.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Map<DateTime, List<TimeEntry>> _applyFilter(
      Map<DateTime, List<TimeEntry>> grouped) {
    if (widget.filterProjectId == null) return grouped;
    final result = <DateTime, List<TimeEntry>>{};
    for (final entry in grouped.entries) {
      final filtered = entry.value.where((e) {
        if (widget.filterProjectId == '__none__') return e.projectId == null;
        return e.projectId == widget.filterProjectId;
      }).toList();
      if (filtered.isNotEmpty) result[entry.key] = filtered;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _applyFilter(widget.timerState.entriesByDay);

    if (grouped.isEmpty) {
      return GlassmorphicContainer(
        borderRadius: 20,
        opacity: Theme.of(context).brightness == Brightness.dark ? 0.90 : 0.92,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined,
                  size: 56,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white24
                      : Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                widget.filterProjectId != null
                    ? 'No entries for this filter'
                    : 'No time tracked this week',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white38
                      : Colors.grey.shade400,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Hit ▶ to start tracking',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white24
                      : Colors.grey.shade300,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GlassmorphicContainer(
      borderRadius: 20,
      opacity: Theme.of(context).brightness == Brightness.dark ? 0.90 : 0.92,
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final date = grouped.keys.elementAt(index);
          final entries = grouped[date]!;
          return _DayGroup(
            date: date,
            entries: entries,
            timerState: widget.timerState,
            themeState: widget.themeState,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Day Group
// ─────────────────────────────────────────────────────────────────────────────

class _DayGroup extends StatelessWidget {
  final DateTime date;
  final List<TimeEntry> entries;
  final TimerState timerState;
  final ThemeState themeState;

  const _DayGroup({
    required this.date,
    required this.entries,
    required this.timerState,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = timerState.dailyTotal(date);
    final isToday = _isToday(date);

    final dateLabel = isToday
        ? 'Today · ${DateFormat('MMM d').format(date)}'
        : DateFormat('EEE, MMM d').format(date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day header
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isToday
                      ? themeState.accentColor
                      : (isDark ? Colors.white70 : Colors.grey.shade600),
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(height: 1),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDurationShort(total),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isToday
                          ? themeState.accentColor
                          : (isDark ? Colors.white70 : Colors.grey.shade700),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Entry tiles
        ...entries.map(
          (entry) => _EntryTile(
            entry: entry,
            timerState: timerState,
            themeState: themeState,
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry Tile
// ─────────────────────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  final TimeEntry entry;
  final TimerState timerState;
  final ThemeState themeState;

  const _EntryTile({
    required this.entry,
    required this.timerState,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    final project = timerState.projectForId(entry.projectId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRunning = entry.isRunning;
    final accent = themeState.accentColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
        border: isRunning
            ? Border.all(
                color: accent.withValues(alpha: 0.4),
                width: 1.5,
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Color dot (pulsing when running)
            _ColorDot(color: project?.color ?? Colors.grey.shade400, pulse: isRunning),
            const SizedBox(width: 12),

            // Description + project label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.description.isEmpty ? '(no description)' : entry.description,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: entry.description.isEmpty
                          ? (isDark ? Colors.white38 : Colors.grey.shade400)
                          : (isDark ? Colors.white : Colors.grey.shade800),
                      fontStyle: entry.description.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (project != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      project.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: project.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Time range
            Text(
              _timeRange(entry),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 16),

            // Duration
            Text(
              _formatDuration(entry.elapsed),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isRunning ? accent : (isDark ? Colors.white70 : Colors.grey.shade700),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),

            // Delete
            InkWell(
              onTap: () => _confirmDelete(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeRange(TimeEntry entry) {
    final start = DateFormat('HH:mm').format(entry.startTime);
    final end = entry.endTime != null
        ? DateFormat('HH:mm').format(entry.endTime!)
        : '–';
    return '$start – $end';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Entry',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to delete this time entry?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await timerState.deleteEntry(entry.id);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing color dot
// ─────────────────────────────────────────────────────────────────────────────

class _ColorDot extends StatefulWidget {
  final Color color;
  final bool pulse;

  const _ColorDot({required this.color, required this.pulse});

  @override
  State<_ColorDot> createState() => _ColorDotState();
}

class _ColorDotState extends State<_ColorDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_ColorDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

String _formatDuration(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String _formatDurationShort(Duration d) {
  if (d.inHours > 0) {
    final m = d.inMinutes % 60;
    return m > 0 ? '${d.inHours}h ${m}m' : '${d.inHours}h';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }
  return '${d.inSeconds}s';
}
