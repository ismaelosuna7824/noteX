import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/time_entry.dart';
import '../../domain/services/day_column_layout.dart';
import '../state/theme_state.dart';
import 'glassmorphic_container.dart';
import '../state/timer_state.dart';

/// The week as a grid: seven day columns against the hours of the day.
///
/// A list answers "what did I do"; this answers "when, and where are the
/// holes". The same entries, read the way a day is actually shaped.
class TimerCalendarView extends StatefulWidget {
  const TimerCalendarView({
    super.key,
    required this.entriesByDay,
    required this.timerState,
    required this.themeState,
    required this.onEntryTap,
  });

  final Map<DateTime, List<TimeEntry>> entriesByDay;
  final TimerState timerState;
  final ThemeState themeState;
  final ValueChanged<TimeEntry> onEntryTap;

  @override
  State<TimerCalendarView> createState() => _TimerCalendarViewState();
}

class _TimerCalendarViewState extends State<TimerCalendarView> {
  final ScrollController _scroll = ScrollController();

  /// Pixels per hour. Tall enough that a half-hour block can still hold a
  /// word, short enough that a working day fits without scrolling.
  static const _hourHeight = 52.0;
  static const _gutter = 54.0;

  @override
  void initState() {
    super.initState();
    // Opens on the working day rather than at midnight, which is eight hours
    // of empty grid before anything a person did.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = (_earliestHour() - 1).clamp(0, 23) * _hourHeight;
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _earliestHour() {
    var earliest = 9;
    for (final day in widget.entriesByDay.values) {
      for (final entry in day) {
        if (entry.startTime.hour < earliest) earliest = entry.startTime.hour;
      }
    }
    return earliest;
  }

  /// The seven days of the week the loaded entries belong to.
  List<DateTime> get _days {
    final keys = widget.entriesByDay.keys.toList()..sort();
    final anchor = keys.isEmpty ? DateTime.now() : keys.last;
    final monday = DateTime(anchor.year, anchor.month, anchor.day)
        .subtract(Duration(days: anchor.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    final ts = widget.themeState;
    final line = ts.editorTextColor.withValues(alpha: 0.08);
    final days = _days;
    final now = DateTime.now();

    // The same glass the list sits on. Over a wallpaper, a bare grid is a
    // handful of hairlines and unreadable text floating on someone's photo.
    return GlassmorphicContainer(
      borderRadius: 20,
      opacity: ts.editorBgColor.computeLuminance() > 0.5 ? 0.92 : 0.90,
      color: ts.editorBgColor,
      child: Column(
        children: [
          _DayHeaderRow(days: days, themeState: ts, gutter: _gutter),
          Divider(height: 1, color: line),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: _hourHeight * 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HourGutter(
                      width: _gutter,
                      hourHeight: _hourHeight,
                      themeState: ts,
                    ),
                    ...days.map(
                      (day) => Expanded(
                        child: _DayColumn(
                          day: day,
                          entries: _entriesFor(day),
                          now: now,
                          hourHeight: _hourHeight,
                          timerState: widget.timerState,
                          themeState: ts,
                          onEntryTap: widget.onEntryTap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TimeEntry> _entriesFor(DateTime day) {
    for (final key in widget.entriesByDay.keys) {
      if (key.year == day.year &&
          key.month == day.month &&
          key.day == day.day) {
        return widget.entriesByDay[key]!;
      }
    }
    return const [];
  }
}

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({
    required this.days,
    required this.themeState,
    required this.gutter,
  });

  final List<DateTime> days;
  final ThemeState themeState;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: gutter),
          ...days.map((day) {
            final isToday = day.year == now.year &&
                day.month == now.month &&
                day.day == now.day;

            return Expanded(
              child: Column(
                children: [
                  Text(
                    DateFormat('EEE').format(day),
                    style: TextStyle(
                      fontSize: 11,
                      color: themeState.editorMutedTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? BoxDecoration(
                            color: themeState.accentColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isToday ? FontWeight.w700 : FontWeight.w500,
                        color: isToday
                            ? themeState.accentColor
                            : themeState.editorTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter({
    required this.width,
    required this.hourHeight,
    required this.themeState,
  });

  final double width;
  final double hourHeight;
  final ThemeState themeState;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: List.generate(24, (hour) {
          return SizedBox(
            height: hourHeight,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Transform.translate(
                  // Lifted onto its own gridline: a label sitting below the
                  // line it names reads as belonging to the hour after it.
                  offset: const Offset(0, -6),
                  child: Text(
                    hour == 0 ? '' : DateFormat('HH:00').format(
                        DateTime(2000, 1, 1, hour)),
                    style: TextStyle(
                      fontSize: 10,
                      color: themeState.editorMutedTextColor
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.entries,
    required this.now,
    required this.hourHeight,
    required this.timerState,
    required this.themeState,
    required this.onEntryTap,
  });

  final DateTime day;
  final List<TimeEntry> entries;
  final DateTime now;
  final double hourHeight;
  final TimerState timerState;
  final ThemeState themeState;
  final ValueChanged<TimeEntry> onEntryTap;

  @override
  Widget build(BuildContext context) {
    final line = themeState.editorTextColor.withValues(alpha: 0.08);
    final placed = layoutDayColumn(entries, now);
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            // Hour lines.
            for (var hour = 1; hour < 24; hour++)
              Positioned(
                top: hour * hourHeight,
                left: 0,
                right: 0,
                child: Divider(height: 1, color: line),
              ),

            if (isToday)
              Positioned(
                top: (now.hour + now.minute / 60) * hourHeight,
                left: 0,
                right: 0,
                child: Container(
                  height: 1.5,
                  color: themeState.accentColor.withValues(alpha: 0.8),
                ),
              ),

            ...placed.map((p) {
              final start = p.entry.startTime;
              final end = p.entry.endTime ?? now;
              final top = (start.hour + start.minute / 60) * hourHeight;
              final rawHeight =
                  end.difference(start).inMinutes / 60 * hourHeight;

              final width = constraints.maxWidth / p.columns;

              return Positioned(
                top: top,
                left: width * p.column,
                width: width,
                // A one-minute entry is still an entry: below this it becomes
                // a line nobody can aim at.
                height: rawHeight.clamp(22.0, double.infinity),
                child: _EntryBlock(
                  entry: p.entry,
                  color: timerState.projectForId(p.entry.projectId)?.color ??
                      themeState.accentColor,
                  themeState: themeState,
                  onTap: () => onEntryTap(p.entry),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _EntryBlock extends StatelessWidget {
  const _EntryBlock({
    required this.entry,
    required this.color,
    required this.themeState,
    required this.onTap,
  });

  final TimeEntry entry;
  final Color color;
  final ThemeState themeState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      child: Material(
        color: color.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              // A rail on the leading edge, so blocks stacked side by side
              // still read as separate pieces of work.
              border: Border(left: BorderSide(color: color, width: 2.5)),
            ),
            // A twenty-minute block is barely a line tall. The label has to
            // fit the time it represents, not the other way round: anything
            // that does not fit is dropped, starting with the start time.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final label = Text(
                  entry.description.isEmpty
                      ? '(no description)'
                      : entry.description,
                  maxLines: constraints.maxHeight >= 42 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: themeState.editorTextColor,
                  ),
                );

                if (constraints.maxHeight < 28) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: label,
                    ),
                  );
                }

                return ClipRect(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      label,
                      Text(
                        DateFormat('HH:mm').format(entry.startTime),
                        style: TextStyle(
                          fontSize: 9.5,
                          color: themeState.editorMutedTextColor,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
