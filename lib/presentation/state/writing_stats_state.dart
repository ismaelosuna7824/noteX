import 'package:flutter/material.dart';

import '../../domain/entities/note.dart';
import '../../domain/services/writing_activity.dart';

/// Exposes writing activity — daily note counts and the current streak — to
/// the UI.
///
/// Everything is derived from the notes by [WritingActivity] on each refresh,
/// so nothing needs persisting and history is correct the first time it is
/// asked for. The previous version kept a running tally in a JSON file and
/// only ever wrote today's entry: any day the app was not opened disappeared,
/// and the streak measured app launches rather than writing.
class WritingStatsState extends ChangeNotifier {
  WritingActivitySummary _summary = const WritingActivitySummary(
    countsByDay: {},
    streak: 0,
  );

  int get currentStreak => _summary.streak;

  /// Notes written or edited today.
  int get todayNoteCount => _summary.countOn(DateTime.now());

  int get yesterdayNoteCount =>
      _summary.countOn(DateTime.now().subtract(const Duration(days: 1)));

  /// Last 7 days of note counts (oldest first), for the mini chart.
  List<int> get weeklyNoteCounts =>
      _summary.lastDays(7, today: DateTime.now());

  /// Last 28 days of note counts (oldest first), for an activity heatmap.
  List<int> get monthlyNoteCounts =>
      _summary.lastDays(28, today: DateTime.now());

  /// Last 7 day labels (e.g. "Mon", "Tue"), aligned with [weeklyNoteCounts].
  List<String> get weeklyLabels {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return days[day.weekday - 1];
    });
  }

  /// Recomputes everything from [notes]. Called on app open and after saves.
  void recordActivity(List<Note> notes) {
    _summary = WritingActivity.from(notes, today: DateTime.now());
    notifyListeners();
  }
}
