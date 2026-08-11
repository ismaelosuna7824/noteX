import '../entities/note.dart';

/// Writing activity derived from the notes themselves.
class WritingActivitySummary {
  /// Days with activity, keyed `yyyy-mm-dd`, mapped to how many notes were
  /// touched that day.
  final Map<String, int> countsByDay;

  /// Consecutive days of writing, counting back from today.
  final int streak;

  const WritingActivitySummary({
    required this.countsByDay,
    required this.streak,
  });

  /// Notes touched on [day].
  int countOn(DateTime day) => countsByDay[WritingActivity.dayKey(day)] ?? 0;

  /// The last [days] daily counts ending on [today], oldest first.
  List<int> lastDays(int days, {required DateTime today}) => List.generate(
        days,
        (i) => countOn(today.subtract(Duration(days: days - 1 - i))),
      );
}

/// Computes writing activity from a note library.
///
/// Pure domain logic — no I/O, no Flutter, no clock. `today` is passed in so
/// every rule here is testable without waiting for midnight.
///
/// This is derived, not accumulated. An earlier version kept a running tally
/// in a JSON file and only ever wrote today's entry, so any day the app was
/// not opened vanished from history and the streak tracked app launches rather
/// than writing. Deriving from the notes makes the past correct by
/// construction.
class WritingActivity {
  const WritingActivity._();

  /// Builds the summary for [notes] as of [today].
  ///
  /// A note counts for the day it was created AND the day it was last edited.
  /// Those are the only two moments a note records, and both are real work:
  /// starting something on Monday and coming back to it on Friday should light
  /// up both days. A note created and last touched the same day counts once.
  ///
  /// Empty and trashed notes are ignored — neither represents writing.
  static WritingActivitySummary from(
    List<Note> notes, {
    required DateTime today,
  }) {
    final counts = <String, int>{};

    for (final note in notes) {
      if (note.isEmpty || note.isDeleted) continue;

      final days = <String>{
        dayKey(note.createdAt),
        dayKey(note.updatedAt),
      };
      for (final day in days) {
        counts[day] = (counts[day] ?? 0) + 1;
      }
    }

    return WritingActivitySummary(
      countsByDay: counts,
      streak: _streak(counts, today),
    );
  }

  /// Consecutive active days ending today.
  ///
  /// When today has no activity yet the count runs from yesterday instead, so
  /// a streak is not reported as broken at nine in the morning — it only ends
  /// once a whole day has passed with nothing written.
  static int _streak(Map<String, int> counts, DateTime today) {
    var cursor = today;
    if ((counts[dayKey(cursor)] ?? 0) == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
      if ((counts[dayKey(cursor)] ?? 0) == 0) return 0;
    }

    var streak = 0;
    while ((counts[dayKey(cursor)] ?? 0) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Calendar-day key, local time. Timestamps within a day must collapse to
  /// one bucket or every note would be its own "day".
  static String dayKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
