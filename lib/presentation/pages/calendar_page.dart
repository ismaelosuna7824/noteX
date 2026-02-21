import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../../domain/entities/note.dart';

/// Calendar view for navigating notes by date.
///
/// Uses white card design matching the editor style.
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
                          color: isSelected ? Colors.white : Colors.black87,
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
    final accentColor = widget.themeState.accentColor;
    final selectedNotes =
        _selectedDay != null ? _getNotesForDay(_selectedDay!) : <Note>[];
    final now = DateTime.now();
    final isCurrentMonth =
        _focusedDay.year == now.year && _focusedDay.month == now.month;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          // Calendar in a white card
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
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

          // Selected day notes in a white card
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
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
                  Divider(color: Colors.grey.shade200),
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
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No notes for this day',
                                  style:
                                      TextStyle(color: Colors.grey.shade400),
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
                                      borderRadius:
                                          BorderRadius.circular(12),
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
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
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
                                                color: Colors.grey.shade500,
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
