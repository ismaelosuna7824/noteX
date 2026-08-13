import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/task_status_migration.dart';

/// Tests [backfillTaskStatus] directly rather than through `onUpgrade`.
///
/// `AppDatabase.forTesting(...)` runs `onCreate`, not `onUpgrade`, so a v18
/// row is seeded here at its pre-backfill shape — `status` left at its
/// column DEFAULT (`'todo'`), `is_completed`/`sync_status` set explicitly —
/// and [backfillTaskStatus] is invoked directly, exactly as `onUpgrade`
/// calls it in the real migration ladder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  Future<void> seedRow({
    required String id,
    bool isCompleted = false,
    String syncStatus = 'localOnly',
    String? status,
  }) async {
    await db.into(db.taskEntries).insert(
          TaskEntriesCompanion.insert(
            id: id,
            scheduledDate: Value(DateTime(2026, 1, 1)),
            isCompleted: Value(isCompleted),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: Value(syncStatus),
            status: status == null ? const Value.absent() : Value(status),
          ),
        );
  }

  Future<TaskEntry> fetch(String id) async {
    return (db.select(db.taskEntries)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('status backfill (is_completed → status)', () {
    test('is_completed = 1 backfills status to done', () async {
      await seedRow(id: 'done-row', isCompleted: true);

      await backfillTaskStatus(db);

      final row = await fetch('done-row');
      expect(row.status, 'done');
    });

    test('is_completed = 0 leaves status at todo', () async {
      await seedRow(id: 'todo-row', isCompleted: false);

      await backfillTaskStatus(db);

      final row = await fetch('todo-row');
      expect(row.status, 'todo');
    });

    test('a pre-set doing row is untouched on re-run', () async {
      await seedRow(id: 'doing-row', isCompleted: false, status: 'doing');

      await backfillTaskStatus(db);
      await backfillTaskStatus(db); // re-run: not transactional, must be idempotent

      final row = await fetch('doing-row');
      expect(row.status, 'doing');
    });

    test('status_changed_at stays NULL — a backfill is not a real transition',
        () async {
      await seedRow(id: 'done-row', isCompleted: true);

      await backfillTaskStatus(db);

      final row = await fetch('done-row');
      expect(row.statusChangedAt, isNull);
    });
  });

  group('status_pending_push backfill (predicate regression guard)', () {
    test('a localOnly row is flagged for push', () async {
      await seedRow(id: 'local-row', syncStatus: 'localOnly');

      await backfillTaskStatus(db);

      final row = await fetch('local-row');
      expect(row.statusPendingPush, isTrue);
    });

    // Named after the hazard: `!= 'synced'` also matches `pendingSync`, which
    // HAS a remote copy — flagging it lets an upgrading client push a stale
    // backfilled status over newer remote state via a path the M8 recency
    // gate cannot see (push runs before pull). This assertion is what stops
    // the predicate drifting back from `= 'localOnly'` to `!= 'synced'`.
    test('a pendingSync row is left unflagged — it already has a remote copy',
        () async {
      await seedRow(id: 'pending-row', syncStatus: 'pendingSync');

      await backfillTaskStatus(db);

      final row = await fetch('pending-row');
      expect(row.statusPendingPush, isFalse);
    });

    test('a synced row is left unflagged', () async {
      await seedRow(id: 'synced-row', syncStatus: 'synced');

      await backfillTaskStatus(db);

      final row = await fetch('synced-row');
      expect(row.statusPendingPush, isFalse);
    });
  });
}
