import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/reminder.dart';
import 'package:notex/domain/value_objects/sync_status.dart';

/// Characterization tests for [Reminder], written BEFORE the task-tracker
/// rename touches any `lib/` code. These pin down today's behavior so a
/// later mechanical rename cannot silently change it.
void main() {
  group('Reminder.create', () {
    test('normalizes scheduledDate to local noon regardless of input time',
        () {
      final reminder = Reminder.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4, 23, 45, 10),
      );

      expect(reminder.scheduledDate, DateTime(2026, 3, 4, 12, 0, 0));
    });

    test('normalizes even when the input time is already noon', () {
      final reminder = Reminder.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4, 12, 0, 0),
      );

      expect(reminder.scheduledDate, DateTime(2026, 3, 4, 12, 0, 0));
    });

    test('sets defaults: not completed, version 1, localOnly, no userId', () {
      final reminder = Reminder.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
      );

      expect(reminder.isCompleted, isFalse);
      expect(reminder.completedAt, isNull);
      expect(reminder.version, 1);
      expect(reminder.syncStatus, SyncStatus.localOnly);
      expect(reminder.userId, isNull);
      expect(reminder.deletedAt, isNull);
    });

    test('stamps createdAt and updatedAt to the same "now" instant', () {
      final before = DateTime.now();
      final reminder = Reminder.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
      );
      final after = DateTime.now();

      expect(reminder.createdAt, reminder.updatedAt);
      expect(
        reminder.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        reminder.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('carries userId through when provided', () {
      final reminder = Reminder.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        userId: 'user-1',
      );

      expect(reminder.userId, 'user-1');
    });
  });

  group('Reminder.isForDate', () {
    final reminder = Reminder(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4, 12, 0, 0),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('matches same year/month/day, ignoring time of day', () {
      expect(reminder.isForDate(DateTime(2026, 3, 4)), isTrue);
      expect(reminder.isForDate(DateTime(2026, 3, 4, 23, 59, 59)), isTrue);
      expect(reminder.isForDate(DateTime(2026, 3, 4, 0, 0, 0)), isTrue);
    });

    test('does not match a different day, month, or year', () {
      expect(reminder.isForDate(DateTime(2026, 3, 5)), isFalse);
      expect(reminder.isForDate(DateTime(2026, 4, 4)), isFalse);
      expect(reminder.isForDate(DateTime(2027, 3, 4)), isFalse);
    });
  });

  group('Reminder.markCompleted', () {
    test('sets isCompleted and stamps completedAt/updatedAt to now', () {
      final reminder = Reminder(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final completed = reminder.markCompleted();

      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);
      expect(completed.updatedAt.isAfter(reminder.updatedAt), isTrue);
      // createdAt and identity fields are untouched.
      expect(completed.id, reminder.id);
      expect(completed.createdAt, reminder.createdAt);
    });
  });

  group('Reminder.markDeleted', () {
    test('sets deletedAt, bumps updatedAt, and forces pendingSync', () {
      final reminder = Reminder(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.localOnly,
      );

      final deleted = reminder.markDeleted();

      expect(deleted.deletedAt, isNotNull);
      expect(deleted.updatedAt.isAfter(reminder.updatedAt), isTrue);
      expect(deleted.syncStatus, SyncStatus.pendingSync);
      expect(deleted.isDeleted, isTrue);
      expect(reminder.isDeleted, isFalse);
    });
  });

  group('Reminder.copyWith — _Unset sentinel semantics', () {
    final base = Reminder(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      completedAt: DateTime(2026, 3, 1),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      deletedAt: DateTime(2026, 3, 2),
      userId: 'user-1',
    );

    test('omitting a sentinel-backed field preserves its current value', () {
      final copy = base.copyWith(title: 'New title');

      expect(copy.completedAt, base.completedAt);
      expect(copy.deletedAt, base.deletedAt);
      expect(copy.userId, base.userId);
      expect(copy.title, 'New title');
    });

    test('explicitly passing null clears a sentinel-backed field', () {
      final copy = base.copyWith(
        completedAt: null,
        deletedAt: null,
        userId: null,
      );

      expect(copy.completedAt, isNull);
      expect(copy.deletedAt, isNull);
      expect(copy.userId, isNull);
      // Untouched fields remain as-is.
      expect(copy.title, base.title);
      expect(copy.scheduledDate, base.scheduledDate);
    });

    test('passing a value overwrites a sentinel-backed field', () {
      final newDeletedAt = DateTime(2026, 5, 1);
      final copy = base.copyWith(deletedAt: newDeletedAt);

      expect(copy.deletedAt, newDeletedAt);
    });

    test('calling copyWith with no arguments is a full no-op copy', () {
      final copy = base.copyWith();

      expect(copy.id, base.id);
      expect(copy.title, base.title);
      expect(copy.scheduledDate, base.scheduledDate);
      expect(copy.isCompleted, base.isCompleted);
      expect(copy.completedAt, base.completedAt);
      expect(copy.createdAt, base.createdAt);
      expect(copy.updatedAt, base.updatedAt);
      expect(copy.version, base.version);
      expect(copy.deletedAt, base.deletedAt);
      expect(copy.syncStatus, base.syncStatus);
      expect(copy.userId, base.userId);
    });
  });

  group('Reminder equality', () {
    test('two reminders with the same id are equal regardless of other fields',
        () {
      final a = Reminder(
        id: 'r1',
        title: 'A',
        scheduledDate: DateTime(2026, 3, 4),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final b = Reminder(
        id: 'r1',
        title: 'B',
        scheduledDate: DateTime(2026, 5, 1),
        createdAt: DateTime(2026, 2, 2),
        updatedAt: DateTime(2026, 2, 2),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
