import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';

/// Characterization tests for [DriftTaskRepository], written BEFORE the
/// task-tracker rename touches any `lib/` code. `getPending`'s carry-over
/// query in particular has zero prior coverage and is the exact query the
/// rename must preserve.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;

  Task buildTask({
    required String id,
    String title = 'Task',
    required DateTime scheduledDate,
    bool isCompleted = false,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus syncStatus = SyncStatus.localOnly,
    String? userId,
  }) {
    return Task(
      id: id,
      title: title,
      scheduledDate: scheduledDate,
      isCompleted: isCompleted,
      completedAt: completedAt,
      createdAt: createdAt ?? _fixedCreatedAt,
      updatedAt: updatedAt ?? _fixedCreatedAt,
      deletedAt: deletedAt,
      syncStatus: syncStatus,
      userId: userId,
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('save + getById — round trip', () {
    test('every field survives a save/read round trip', () async {
      final task = buildTask(
        id: 'r1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4, 12),
        isCompleted: true,
        completedAt: DateTime(2026, 3, 3, 9),
        createdAt: DateTime(2026, 1, 1, 8),
        updatedAt: DateTime(2026, 1, 2, 9),
        syncStatus: SyncStatus.pendingSync,
        userId: 'user-1',
      );

      await repository.save(task);
      final fetched = await repository.getById('r1');

      expect(fetched, isNotNull);
      expect(fetched!.id, task.id);
      expect(fetched.title, task.title);
      expect(fetched.scheduledDate, task.scheduledDate);
      expect(fetched.isCompleted, task.isCompleted);
      expect(fetched.completedAt, task.completedAt);
      expect(fetched.createdAt, task.createdAt);
      expect(fetched.updatedAt, task.updatedAt);
      expect(fetched.syncStatus, task.syncStatus);
      expect(fetched.userId, task.userId);
    });

    test('getById returns null for a missing id', () async {
      expect(await repository.getById('missing'), isNull);
    });

    test('save upserts — saving an existing id updates in place', () async {
      await repository.save(
        buildTask(id: 'r1', title: 'Original', scheduledDate: DateTime(2026, 3, 4)),
      );
      await repository.save(
        buildTask(id: 'r1', title: 'Updated', scheduledDate: DateTime(2026, 3, 4)),
      );

      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.single.title, 'Updated');
    });
  });

  group('getAll', () {
    test('excludes soft-deleted tasks', () async {
      await repository.save(buildTask(id: 'alive', scheduledDate: DateTime(2026, 3, 4)));
      await repository.save(buildTask(
        id: 'dead',
        scheduledDate: DateTime(2026, 3, 4),
        deletedAt: DateTime(2026, 3, 5),
      ));

      final all = await repository.getAll();

      expect(all.map((r) => r.id), ['alive']);
    });

    test('orders by scheduledDate ascending', () async {
      await repository.save(buildTask(id: 'late', scheduledDate: DateTime(2026, 3, 10)));
      await repository.save(buildTask(id: 'early', scheduledDate: DateTime(2026, 3, 1)));
      await repository.save(buildTask(id: 'mid', scheduledDate: DateTime(2026, 3, 5)));

      final all = await repository.getAll();

      expect(all.map((r) => r.id).toList(), ['early', 'mid', 'late']);
    });
  });

  group('getBySyncStatus', () {
    test('filters tasks by exact sync status', () async {
      await repository.save(buildTask(
        id: 'local',
        scheduledDate: DateTime(2026, 3, 4),
        syncStatus: SyncStatus.localOnly,
      ));
      await repository.save(buildTask(
        id: 'pending',
        scheduledDate: DateTime(2026, 3, 4),
        syncStatus: SyncStatus.pendingSync,
      ));
      await repository.save(buildTask(
        id: 'synced',
        scheduledDate: DateTime(2026, 3, 4),
        syncStatus: SyncStatus.synced,
      ));

      final pending = await repository.getBySyncStatus(SyncStatus.pendingSync);

      expect(pending.map((r) => r.id), ['pending']);
    });
  });

  group('getModifiedSince', () {
    test('returns only tasks with updatedAt strictly after the cutoff',
        () async {
      await repository.save(buildTask(
        id: 'old',
        scheduledDate: DateTime(2026, 3, 4),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repository.save(buildTask(
        id: 'new',
        scheduledDate: DateTime(2026, 3, 4),
        updatedAt: DateTime(2026, 6, 1),
      ));

      final modified = await repository.getModifiedSince(DateTime(2026, 3, 1));

      expect(modified.map((r) => r.id), ['new']);
    });
  });

  group('getPending — carry-over invariant', () {
    test('excludes completed tasks regardless of date', () async {
      await repository.save(buildTask(
        id: 'done',
        scheduledDate: DateTime(2026, 3, 1),
        isCompleted: true,
        completedAt: DateTime(2026, 3, 1),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending, isEmpty);
    });

    test('excludes tasks scheduled strictly in the future', () async {
      await repository.save(buildTask(
        id: 'future',
        scheduledDate: DateTime(2026, 3, 20),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending, isEmpty);
    });

    test('includes overdue (past-due, uncompleted) tasks — carry-over',
        () async {
      await repository.save(buildTask(
        id: 'overdue',
        scheduledDate: DateTime(2026, 3, 1),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending.map((r) => r.id), ['overdue']);
    });

    test('includes a task scheduled exactly on upToDate', () async {
      await repository.save(buildTask(
        id: 'today',
        scheduledDate: DateTime(2026, 3, 10, 12),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending.map((r) => r.id), ['today']);
    });

    test('excludes soft-deleted tasks even if overdue and uncompleted',
        () async {
      await repository.save(buildTask(
        id: 'deleted-overdue',
        scheduledDate: DateTime(2026, 3, 1),
        deletedAt: DateTime(2026, 3, 2),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending, isEmpty);
    });

    test('orders results by scheduledDate ascending', () async {
      await repository.save(buildTask(id: 'b', scheduledDate: DateTime(2026, 3, 5)));
      await repository.save(buildTask(id: 'a', scheduledDate: DateTime(2026, 3, 1)));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending.map((r) => r.id).toList(), ['a', 'b']);
    });
  });

  group('delete', () {
    test('hard-deletes the row', () async {
      await repository.save(buildTask(id: 'r1', scheduledDate: DateTime(2026, 3, 4)));
      await repository.delete('r1');

      expect(await repository.getById('r1'), isNull);
    });
  });
}

final _fixedCreatedAt = DateTime.utc(2026, 1, 1, 8);
