import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/time_entry.dart';
import 'package:notex/domain/value_objects/sync_status.dart';

/// Slice 3: timer↔task link. Written before any [TimeEntry] test existed in
/// this repo — [taskId] is entirely new, so these cover both the field
/// itself and the existing behavior it must not disturb.
void main() {
  test('a timer with no taskId behaves exactly as before (default null)', () {
    final entry = TimeEntry(
      id: 'e1',
      description: 'Fix bug',
      startTime: DateTime(2026, 1, 1, 9),
      updatedAt: DateTime(2026, 1, 1, 9),
    );

    expect(entry.taskId, isNull);
  });

  test('a timer can be created linked to a task', () {
    final entry = TimeEntry(
      id: 'e1',
      description: 'Fix bug',
      taskId: 't1',
      startTime: DateTime(2026, 1, 1, 9),
      updatedAt: DateTime(2026, 1, 1, 9),
    );

    expect(entry.taskId, 't1');
  });

  group('stop()', () {
    test(
      'preserves taskId — stop() rebuilds field-by-field, not via copyWith, '
      'so a field added to the constructor and forgotten here is silently '
      'dropped the instant the user stops the timer',
      () {
        final running = TimeEntry(
          id: 'e1',
          description: 'Fix bug',
          taskId: 't1',
          startTime: DateTime(2026, 1, 1, 9),
          updatedAt: DateTime(2026, 1, 1, 9),
        );

        final stopped = running.stop();

        expect(stopped.taskId, 't1');
      },
    );

    test('preserves a null taskId — a task-less timer stays task-less', () {
      final running = TimeEntry(
        id: 'e1',
        description: 'Fix bug',
        startTime: DateTime(2026, 1, 1, 9),
        updatedAt: DateTime(2026, 1, 1, 9),
      );

      expect(running.stop().taskId, isNull);
    });

    test('still sets endTime and marks pendingSync (unchanged behavior)', () {
      final running = TimeEntry(
        id: 'e1',
        description: 'Fix bug',
        startTime: DateTime(2026, 1, 1, 9),
        updatedAt: DateTime(2026, 1, 1, 9),
        syncStatus: SyncStatus.synced,
      );

      final stopped = running.stop();

      expect(stopped.isRunning, isFalse);
      expect(stopped.endTime, isNotNull);
      expect(stopped.syncStatus, SyncStatus.pendingSync);
    });
  });

  group('copyWith taskId', () {
    test('omitting taskId preserves the existing value', () {
      final entry = TimeEntry(
        id: 'e1',
        description: 'Fix bug',
        taskId: 't1',
        startTime: DateTime(2026, 1, 1, 9),
        updatedAt: DateTime(2026, 1, 1, 9),
      );

      final copy = entry.copyWith(description: 'Fix bug harder');

      expect(copy.taskId, 't1');
    });

    test('passing null explicitly clears taskId', () {
      final entry = TimeEntry(
        id: 'e1',
        description: 'Fix bug',
        taskId: 't1',
        startTime: DateTime(2026, 1, 1, 9),
        updatedAt: DateTime(2026, 1, 1, 9),
      );

      final copy = entry.copyWith(taskId: null);

      expect(copy.taskId, isNull);
    });

    test('passing a value sets taskId', () {
      final entry = TimeEntry(
        id: 'e1',
        description: 'Fix bug',
        startTime: DateTime(2026, 1, 1, 9),
        updatedAt: DateTime(2026, 1, 1, 9),
      );

      final copy = entry.copyWith(taskId: 't2');

      expect(copy.taskId, 't2');
    });
  });
}
