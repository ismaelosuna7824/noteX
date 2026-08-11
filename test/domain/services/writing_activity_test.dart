import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/domain/services/writing_activity.dart';

void main() {
  final today = DateTime(2026, 8, 10, 14, 30);

  DateTime daysAgo(int n) => today.subtract(Duration(days: n));

  Note note({
    String id = 'n',
    String content = 'real content',
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      Note(
        id: id,
        title: 'T',
        content: content,
        createdAt: createdAt ?? today,
        updatedAt: updatedAt ?? createdAt ?? today,
        deletedAt: deletedAt,
      );

  WritingActivitySummary summarise(List<Note> notes) =>
      WritingActivity.from(notes, today: today);

  group('daily counts', () {
    test('counts a note on the day it was written', () {
      final summary = summarise([note(createdAt: daysAgo(3))]);
      expect(summary.countOn(daysAgo(3)), 1);
    });

    test('a note counts for both the day it started and the day it was edited',
        () {
      final summary = summarise([
        note(createdAt: daysAgo(5), updatedAt: daysAgo(1)),
      ]);

      expect(summary.countOn(daysAgo(5)), 1);
      expect(summary.countOn(daysAgo(1)), 1);
    });

    test('a note written and finished the same day counts once', () {
      final summary = summarise([
        note(createdAt: daysAgo(2), updatedAt: daysAgo(2).add(const Duration(hours: 3))),
      ]);

      expect(summary.countOn(daysAgo(2)), 1);
    });

    test('times within a day collapse into one bucket', () {
      final summary = summarise([
        note(id: 'a', createdAt: DateTime(2026, 8, 8, 1)),
        note(id: 'b', createdAt: DateTime(2026, 8, 8, 23, 59)),
      ]);

      expect(summary.countOn(DateTime(2026, 8, 8)), 2);
    });

    test('empty and trashed notes are not writing', () {
      final summary = summarise([
        note(id: 'empty', content: '', createdAt: daysAgo(1)),
        note(id: 'gone', createdAt: daysAgo(1), deletedAt: today),
      ]);

      expect(summary.countOn(daysAgo(1)), 0);
    });

    test('history is recovered from notes, not accumulated over time', () {
      // The whole point: these days were never "recorded live" and still show.
      final summary = summarise([
        note(id: 'a', createdAt: daysAgo(25)),
        note(id: 'b', createdAt: daysAgo(20)),
        note(id: 'c', createdAt: daysAgo(17)),
      ]);

      expect(summary.countOn(daysAgo(25)), 1);
      expect(summary.countOn(daysAgo(20)), 1);
      expect(summary.countOn(daysAgo(17)), 1);
    });
  });

  group('streak', () {
    test('is zero with no notes at all', () {
      expect(summarise([]).streak, 0);
    });

    test('counts consecutive days ending today', () {
      final summary = summarise([
        note(id: 'a', createdAt: today),
        note(id: 'b', createdAt: daysAgo(1)),
        note(id: 'c', createdAt: daysAgo(2)),
      ]);

      expect(summary.streak, 3);
    });

    test('stops at the first missed day', () {
      final summary = summarise([
        note(id: 'a', createdAt: today),
        note(id: 'b', createdAt: daysAgo(1)),
        // nothing on day 2
        note(id: 'c', createdAt: daysAgo(3)),
      ]);

      expect(summary.streak, 2);
    });

    test('survives a morning with nothing written yet', () {
      // Yesterday and the day before have activity; today does not.
      final summary = summarise([
        note(id: 'a', createdAt: daysAgo(1)),
        note(id: 'b', createdAt: daysAgo(2)),
      ]);

      expect(summary.streak, 2);
    });

    test('ends once a whole day passes with nothing written', () {
      final summary = summarise([
        note(id: 'a', createdAt: daysAgo(2)),
        note(id: 'b', createdAt: daysAgo(3)),
      ]);

      expect(summary.streak, 0);
    });

    test('editing an old note today keeps the streak alive', () {
      // The old behaviour only credited creation, so a day spent revising
      // counted as a day of not writing.
      final summary = summarise([
        note(id: 'old', createdAt: daysAgo(30), updatedAt: today),
        note(id: 'yesterday', createdAt: daysAgo(1)),
      ]);

      expect(summary.streak, 2);
    });
  });

  group('lastDays', () {
    test('returns one entry per day, oldest first', () {
      final summary = summarise([
        note(id: 'a', createdAt: today),
        note(id: 'b', createdAt: daysAgo(2)),
      ]);

      expect(summary.lastDays(3, today: today), [1, 0, 1]);
    });

    test('days with nothing written come back as zero', () {
      expect(summarise([]).lastDays(7, today: today), List.filled(7, 0));
    });
  });
}
