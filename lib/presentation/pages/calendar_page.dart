import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../../domain/entities/note.dart';

/// Dark-mode card surface — same as home page for visual consistency.
const _kDarkCard = Color(0xFF1A1A2E);

/// Calendar view for navigating notes by date.
///
/// Uses adaptive card design: light white in light mode, dark navy in dark mode.
class CalendarPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const CalendarPage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
  }

  List<Note> _getNotesForDay(DateTime day) {
    return widget.appState.notes.where((n) => n.isForDate(day)).toList();
  }

  Future<void> _showMonthYearPicker(BuildContext context, Color accentColor) async {
    int tempYear = _focusedDay.year;
    int tempMonth = _focusedDay.month;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => setDialogState(() => tempYear--),
                  icon: const Icon(Icons.chevron_left_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  '$tempYear',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                IconButton(
                  onPressed: () => setDialogState(() => tempYear++),
                  icon: const Icon(Icons.chevron_right_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            content: SizedBox(
              width: 280,
              child: GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.4,
                children: List.generate(12, (i) {
                  final isSelected = i + 1 == tempMonth && tempYear == _focusedDay.year;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        tempMonth = i + 1;
                        _focusedDay = DateTime(tempYear, i + 1, 1);
                      });
                      Navigator.of(ctx).pop();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: isSelected ? accentColor : accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _monthShort[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          // Selected always white; unselected adapts to mode
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
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
    final selectedNotes =
        _selectedDay != null ? _getNotesForDay(_selectedDay!) : <Note>[];
    final now = DateTime.now();
    final isCurrentMonth =
        _focusedDay.year == now.year && _focusedDay.month == now.month;

    // Adaptive surface colors
    final cardColor =
        isDark ? _kDarkCard.withValues(alpha: 0.90) : Colors.white.withValues(alpha: 0.95);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.grey.shade200;
    final cardShadow = Colors.black.withValues(alpha: isDark ? 0.30 : 0.04);
    final innerItemBg =
        isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade50;
    final innerItemBorder =
        isDark ? Colors.white.withValues(alpha: 0.10) : Colors.grey.shade200;
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.10) : Colors.grey.shade200;
    final emptyIconColor =
        isDark ? Colors.white.withValues(alpha: 0.20) : Colors.grey.shade300;
    final emptyTextColor =
        isDark ? Colors.white.withValues(alpha: 0.40) : Colors.grey.shade400;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar card
          Expanded(
            flex: 3,
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  TableCalendar<Note>(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    calendarFormat: _calendarFormat,
                    eventLoader: _getNotesForDay,
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });

                      final notes = _getNotesForDay(selectedDay);
                      if (notes.isNotEmpty) {
                        widget.appState.previewNote(notes.first);
                      }
                    },
                    onFormatChanged: (format) {
                      setState(() => _calendarFormat = format);
                    },
                    onPageChanged: (focusedDay) {
                      setState(() => _focusedDay = focusedDay);
                    },
                    onHeaderTapped: (_) => _showMonthYearPicker(context, accentColor),
                    calendarStyle: CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      markerSize: 6,
                      markersMaxCount: 1,
                      outsideDaysVisible: false,
                      // Adapt day text colors to mode
                      defaultTextStyle: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      weekendTextStyle: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey.shade700,
                      ),
                      todayTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      selectedTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      outsideTextStyle: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.20)
                            : Colors.grey.shade300,
                      ),
                      disabledTextStyle: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.20)
                            : Colors.grey.shade300,
                      ),
                      weekNumberTextStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                      ),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                        fontSize: 12,
                      ),
                      weekendStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonDecoration: BoxDecoration(
                        border: Border.all(color: accentColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      formatButtonTextStyle: TextStyle(color: accentColor),
                      titleCentered: true,
                      titleTextStyle: theme.textTheme.titleLarge!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    calendarBuilders: CalendarBuilders(
                      headerTitleBuilder: (context, day) {
                        return GestureDetector(
                          onTap: () => _showMonthYearPicker(context, accentColor),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${_monthNames[day.month - 1]} ${day.year}',
                                style: theme.textTheme.titleLarge!.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                color: accentColor,
                                size: 22,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // "Today" button — only visible when away from current month
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: isCurrentMonth
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _focusedDay = now;
                                _selectedDay = now;
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: accentColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.today_rounded,
                                        size: 16, color: accentColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Back to Today',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: accentColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Selected day notes panel
          Expanded(
            flex: 2,
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
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: accentColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedDay != null
                            ? 'Notes for ${_selectedDay!.month}/${_selectedDay!.day}'
                            : 'Select a date',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Divider(color: dividerColor),
                  const SizedBox(height: 8),
                  Expanded(
                    child: selectedNotes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_note_outlined,
                                  size: 48,
                                  color: emptyIconColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No notes for this day',
                                  style: TextStyle(color: emptyTextColor),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () async {
                                    await widget.appState.createNewNote();
                                    widget.appState.navigateToPage(2);
                                  },
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Create Note'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accentColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: selectedNotes.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final note = selectedNotes[index];
                              return InkWell(
                                onTap: () {
                                  widget.appState.selectNote(note);
                                  widget.appState.navigateToPage(2);
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: innerItemBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: innerItemBorder,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              note.title.isEmpty
                                                  ? 'Untitled'
                                                  : note.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Updated: ${note.updatedAt.hour}:${note.updatedAt.minute.toString().padLeft(2, '0')}',
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.white38
                                                    : Colors.grey.shade500,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 14,
                                        color: accentColor,
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
          ),
        ],
      ),
    );
  }
}
