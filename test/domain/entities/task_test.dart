import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/domain/value_objects/task_status.dart';

/// Characterization tests for [Task] (from the pre-rename `Reminder`),
/// extended for Phase 1.4 (status becomes the source of truth — design D3).
void main() {
  group('Task.create', () {
    test('normalizes scheduledDate to local noon regardless of input time',
        () {
      final task = Task.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4, 23, 45, 10),
      );

      expect(task.scheduledDate, DateTime(2026, 3, 4, 12, 0, 0));
    });

    test('normalizes even when the input time is already noon', () {
      final task = Task.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4, 12, 0, 0),
      );

      expect(task.scheduledDate, DateTime(2026, 3, 4, 12, 0, 0));
    });

    test(
        'sets defaults: todo, not done, version 1, localOnly, no userId',
        () {
      final task = Task.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
      );

      expect(task.status, TaskStatus.todo);
      expect(task.isDone, isFalse);
      expect(task.completedAt, isNull);
      expect(task.version, 1);
      expect(task.syncStatus, SyncStatus.localOnly);
      expect(task.userId, isNull);
      expect(task.deletedAt, isNull);
    });

    test('sets statusPendingPush — the first push always carries status',
        () {
      final task = Task.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
      );

      expect(task.statusPendingPush, isTrue);
    });

    test('stamps createdAt and updatedAt to the same "now" instant', () {
      final before = DateTime.now();
      final task = Task.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
      );
      final after = DateTime.now();

      expect(task.createdAt, task.updatedAt);
      expect(
        task.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        task.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('carries userId through when provided', () {
      final task = Task.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        userId: 'user-1',
      );

      expect(task.userId, 'user-1');
    });
  });

  group('Task.isForDate', () {
    final task = Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4, 12, 0, 0),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('matches same year/month/day, ignoring time of day', () {
      expect(task.isForDate(DateTime(2026, 3, 4)), isTrue);
      expect(task.isForDate(DateTime(2026, 3, 4, 23, 59, 59)), isTrue);
      expect(task.isForDate(DateTime(2026, 3, 4, 0, 0, 0)), isTrue);
    });

    test('does not match a different day, month, or year', () {
      expect(task.isForDate(DateTime(2026, 3, 5)), isFalse);
      expect(task.isForDate(DateTime(2026, 4, 4)), isFalse);
      expect(task.isForDate(DateTime(2027, 3, 4)), isFalse);
    });
  });

  group('Task.isDone', () {
    test('is derived from status, never stored independently', () {
      final todo = Task(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        status: TaskStatus.todo,
      );
      final done = todo.copyWith(status: TaskStatus.done);

      expect(todo.isDone, isFalse);
      expect(done.isDone, isTrue);
    });
  });

  group('Task.transitionTo', () {
    Task buildTask({
      TaskStatus status = TaskStatus.todo,
      String? blockedReason,
      SyncStatus syncStatus = SyncStatus.synced,
      DateTime? completedAt,
    }) {
      return Task(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        status: status,
        blockedReason: blockedReason,
        syncStatus: syncStatus,
        completedAt: completedAt,
      );
    }

    test('sets statusChangedAt and statusPendingPush on every transition',
        () {
      final task = buildTask();

      final next = task.transitionTo(TaskStatus.doing);

      expect(next.status, TaskStatus.doing);
      expect(next.statusChangedAt, isNotNull);
      expect(next.statusPendingPush, isTrue);
      expect(next.updatedAt.isAfter(task.updatedAt), isTrue);
    });

    test('sets completedAt to now when transitioning to done', () {
      final task = buildTask(status: TaskStatus.doing);

      final done = task.transitionTo(TaskStatus.done);

      expect(done.status, TaskStatus.done);
      expect(done.isDone, isTrue);
      expect(done.completedAt, isNotNull);
    });

    test('clears completedAt when leaving done', () {
      final task = buildTask(
        status: TaskStatus.done,
        completedAt: DateTime(2026, 3, 1),
      );

      final reopened = task.transitionTo(TaskStatus.doing);

      expect(reopened.completedAt, isNull);
    });

    test('retains blockedReason when the reason is omitted', () {
      final task = buildTask(
        status: TaskStatus.blocked,
        blockedReason: 'waiting on design review',
      );

      final next = task.transitionTo(TaskStatus.doing);

      expect(next.blockedReason, 'waiting on design review');
    });

    test('retains blockedReason through blocked -> doing -> blocked', () {
      final blocked = buildTask(
        status: TaskStatus.todo,
        blockedReason: 'waiting on design review',
      ).transitionTo(TaskStatus.blocked);

      final doing = blocked.transitionTo(TaskStatus.doing);
      final blockedAgain = doing.transitionTo(TaskStatus.blocked);

      expect(doing.blockedReason, 'waiting on design review');
      expect(blockedAgain.blockedReason, 'waiting on design review');
    });

    test('clears blockedReason only when explicitly passed null', () {
      final task = buildTask(
        status: TaskStatus.blocked,
        blockedReason: 'waiting on design review',
      );

      final next = task.transitionTo(TaskStatus.doing, blockedReason: null);

      expect(next.blockedReason, isNull);
    });

    test('a value passed explicitly overwrites blockedReason', () {
      final task = buildTask(
        status: TaskStatus.blocked,
        blockedReason: 'old reason',
      );

      final next = task.transitionTo(
        TaskStatus.blocked,
        blockedReason: 'new reason',
      );

      expect(next.blockedReason, 'new reason');
    });

    test('keeps localOnly sync status for unauthenticated users', () {
      final task = buildTask(syncStatus: SyncStatus.localOnly);

      final next = task.transitionTo(TaskStatus.doing);

      expect(next.syncStatus, SyncStatus.localOnly);
    });

    test('promotes a synced task to pendingSync', () {
      final task = buildTask(syncStatus: SyncStatus.synced);

      final next = task.transitionTo(TaskStatus.doing);

      expect(next.syncStatus, SyncStatus.pendingSync);
    });
  });

  group('Task.markSynced', () {
    test('clears statusPendingPush and sets syncStatus to synced', () {
      final task = Task.create(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
      );
      expect(task.statusPendingPush, isTrue);

      final synced = task.markSynced();

      expect(synced.statusPendingPush, isFalse);
      expect(synced.syncStatus, SyncStatus.synced);
    });
  });

  group('Task.markDeleted', () {
    test('sets deletedAt, bumps updatedAt, and forces pendingSync', () {
      final task = Task(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.localOnly,
      );

      final deleted = task.markDeleted();

      expect(deleted.deletedAt, isNotNull);
      expect(deleted.updatedAt.isAfter(task.updatedAt), isTrue);
      expect(deleted.syncStatus, SyncStatus.pendingSync);
      expect(deleted.isDeleted, isTrue);
      expect(task.isDeleted, isFalse);
    });

    test('preserves statusPendingPush', () {
      final task = Task(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        statusPendingPush: true,
      );

      final deleted = task.markDeleted();

      expect(deleted.statusPendingPush, isTrue);
    });
  });

  group('Task.copyWith — _Unset sentinel semantics', () {
    final base = Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      completedAt: DateTime(2026, 3, 1),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      deletedAt: DateTime(2026, 3, 2),
      userId: 'user-1',
      blockedReason: 'blocked reason',
      noteId: 'note-1',
    );

    test('omitting a sentinel-backed field preserves its current value', () {
      final copy = base.copyWith(title: 'New title');

      expect(copy.completedAt, base.completedAt);
      expect(copy.deletedAt, base.deletedAt);
      expect(copy.userId, base.userId);
      expect(copy.blockedReason, base.blockedReason);
      expect(copy.noteId, base.noteId);
      expect(copy.title, 'New title');
    });

    test('explicitly passing null clears a sentinel-backed field', () {
      final copy = base.copyWith(
        completedAt: null,
        deletedAt: null,
        userId: null,
        blockedReason: null,
        noteId: null,
      );

      expect(copy.completedAt, isNull);
      expect(copy.deletedAt, isNull);
      expect(copy.userId, isNull);
      expect(copy.blockedReason, isNull);
      expect(copy.noteId, isNull);
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
      expect(copy.status, base.status);
      expect(copy.statusChangedAt, base.statusChangedAt);
      expect(copy.statusPendingPush, base.statusPendingPush);
      expect(copy.completedAt, base.completedAt);
      expect(copy.description, base.description);
      expect(copy.blockedReason, base.blockedReason);
      expect(copy.noteId, base.noteId);
      expect(copy.createdAt, base.createdAt);
      expect(copy.updatedAt, base.updatedAt);
      expect(copy.version, base.version);
      expect(copy.deletedAt, base.deletedAt);
      expect(copy.syncStatus, base.syncStatus);
      expect(copy.userId, base.userId);
    });
  });

  group('Task equality', () {
    test('two tasks with the same id are equal regardless of other fields',
        () {
      final a = Task(
        id: 'r1',
        title: 'A',
        scheduledDate: DateTime(2026, 3, 4),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final b = Task(
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
