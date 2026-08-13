import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/reminder.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_reminder_repository.dart';

/// Characterization tests for [DriftReminderRepository], written BEFORE the
/// task-tracker rename touches any `lib/` code. `getPending`'s carry-over
/// query in particular has zero prior coverage and is the exact query the
/// rename must preserve.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftReminderRepository repository;

  Reminder buildReminder({
    required String id,
    String title = 'Reminder',
    required DateTime scheduledDate,
    bool isCompleted = false,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus syncStatus = SyncStatus.localOnly,
    String? userId,
  }) {
    return Reminder(
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
    repository = DriftReminderRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('save + getById — round trip', () {
    test('every field survives a save/read round trip', () async {
      final reminder = buildReminder(
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

      await repository.save(reminder);
      final fetched = await repository.getById('r1');

      expect(fetched, isNotNull);
      expect(fetched!.id, reminder.id);
      expect(fetched.title, reminder.title);
      expect(fetched.scheduledDate, reminder.scheduledDate);
      expect(fetched.isCompleted, reminder.isCompleted);
      expect(fetched.completedAt, reminder.completedAt);
      expect(fetched.createdAt, reminder.createdAt);
      expect(fetched.updatedAt, reminder.updatedAt);
      expect(fetched.syncStatus, reminder.syncStatus);
      expect(fetched.userId, reminder.userId);
    });

    test('getById returns null for a missing id', () async {
      expect(await repository.getById('missing'), isNull);
    });

    test('save upserts — saving an existing id updates in place', () async {
      await repository.save(
        buildReminder(id: 'r1', title: 'Original', scheduledDate: DateTime(2026, 3, 4)),
      );
      await repository.save(
        buildReminder(id: 'r1', title: 'Updated', scheduledDate: DateTime(2026, 3, 4)),
      );

      final all = await repository.getAll();
      expect(all, hasLength(1));
      expect(all.single.title, 'Updated');
    });
  });

  group('getAll', () {
    test('excludes soft-deleted reminders', () async {
      await repository.save(buildReminder(id: 'alive', scheduledDate: DateTime(2026, 3, 4)));
      await repository.save(buildReminder(
        id: 'dead',
        scheduledDate: DateTime(2026, 3, 4),
        deletedAt: DateTime(2026, 3, 5),
      ));

      final all = await repository.getAll();

      expect(all.map((r) => r.id), ['alive']);
    });

    test('orders by scheduledDate ascending', () async {
      await repository.save(buildReminder(id: 'late', scheduledDate: DateTime(2026, 3, 10)));
      await repository.save(buildReminder(id: 'early', scheduledDate: DateTime(2026, 3, 1)));
      await repository.save(buildReminder(id: 'mid', scheduledDate: DateTime(2026, 3, 5)));

      final all = await repository.getAll();

      expect(all.map((r) => r.id).toList(), ['early', 'mid', 'late']);
    });
  });

  group('getBySyncStatus', () {
    test('filters reminders by exact sync status', () async {
      await repository.save(buildReminder(
        id: 'local',
        scheduledDate: DateTime(2026, 3, 4),
        syncStatus: SyncStatus.localOnly,
      ));
      await repository.save(buildReminder(
        id: 'pending',
        scheduledDate: DateTime(2026, 3, 4),
        syncStatus: SyncStatus.pendingSync,
      ));
      await repository.save(buildReminder(
        id: 'synced',
        scheduledDate: DateTime(2026, 3, 4),
        syncStatus: SyncStatus.synced,
      ));

      final pending = await repository.getBySyncStatus(SyncStatus.pendingSync);

      expect(pending.map((r) => r.id), ['pending']);
    });
  });

  group('getModifiedSince', () {
    test('returns only reminders with updatedAt strictly after the cutoff',
        () async {
      await repository.save(buildReminder(
        id: 'old',
        scheduledDate: DateTime(2026, 3, 4),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repository.save(buildReminder(
        id: 'new',
        scheduledDate: DateTime(2026, 3, 4),
        updatedAt: DateTime(2026, 6, 1),
      ));

      final modified = await repository.getModifiedSince(DateTime(2026, 3, 1));

      expect(modified.map((r) => r.id), ['new']);
    });
  });

  group('getPending — carry-over invariant', () {
    test('excludes completed reminders regardless of date', () async {
      await repository.save(buildReminder(
        id: 'done',
        scheduledDate: DateTime(2026, 3, 1),
        isCompleted: true,
        completedAt: DateTime(2026, 3, 1),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending, isEmpty);
    });

    test('excludes reminders scheduled strictly in the future', () async {
      await repository.save(buildReminder(
        id: 'future',
        scheduledDate: DateTime(2026, 3, 20),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending, isEmpty);
    });

    test('includes overdue (past-due, uncompleted) reminders — carry-over',
        () async {
      await repository.save(buildReminder(
        id: 'overdue',
        scheduledDate: DateTime(2026, 3, 1),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending.map((r) => r.id), ['overdue']);
    });

    test('includes a reminder scheduled exactly on upToDate', () async {
      await repository.save(buildReminder(
        id: 'today',
        scheduledDate: DateTime(2026, 3, 10, 12),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending.map((r) => r.id), ['today']);
    });

    test('excludes soft-deleted reminders even if overdue and uncompleted',
        () async {
      await repository.save(buildReminder(
        id: 'deleted-overdue',
        scheduledDate: DateTime(2026, 3, 1),
        deletedAt: DateTime(2026, 3, 2),
      ));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending, isEmpty);
    });

    test('orders results by scheduledDate ascending', () async {
      await repository.save(buildReminder(id: 'b', scheduledDate: DateTime(2026, 3, 5)));
      await repository.save(buildReminder(id: 'a', scheduledDate: DateTime(2026, 3, 1)));

      final pending = await repository.getPending(DateTime(2026, 3, 10));

      expect(pending.map((r) => r.id).toList(), ['a', 'b']);
    });
  });

  group('delete', () {
    test('hard-deletes the row', () async {
      await repository.save(buildReminder(id: 'r1', scheduledDate: DateTime(2026, 3, 4)));
      await repository.delete('r1');

      expect(await repository.getById('r1'), isNull);
    });
  });
}

final _fixedCreatedAt = DateTime.utc(2026, 1, 1, 8);
