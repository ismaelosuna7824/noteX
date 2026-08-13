import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/reminder/complete_reminder_use_case.dart';
import 'package:notex/domain/entities/reminder.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_reminder_repository.dart';

/// Characterization tests for [CompleteReminderUseCase], written BEFORE the
/// task-tracker rename touches any `lib/` code.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftReminderRepository repository;
  late CompleteReminderUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftReminderRepository(db);
    useCase = CompleteReminderUseCase(repository);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns null when the reminder id does not exist', () async {
    final result = await useCase.execute('missing');

    expect(result, isNull);
  });

  test('marks an existing reminder as completed and persists it', () async {
    await repository.save(Reminder(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1');

    expect(result, isNotNull);
    expect(result!.isCompleted, isTrue);
    expect(result.completedAt, isNotNull);

    final persisted = await repository.getById('r1');
    expect(persisted!.isCompleted, isTrue);
    expect(persisted.completedAt, isNotNull);
  });

  test('preserves localOnly sync status for unauthenticated users', () async {
    await repository.save(Reminder(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.localOnly,
    ));

    final result = await useCase.execute('r1');

    expect(result!.syncStatus, SyncStatus.localOnly);
  });

  test('promotes a synced reminder to pendingSync on completion', () async {
    await repository.save(Reminder(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1');

    expect(result!.syncStatus, SyncStatus.pendingSync);
  });

  test('promotes a pendingSync reminder to pendingSync (stays pending)',
      () async {
    await repository.save(Reminder(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.pendingSync,
    ));

    final result = await useCase.execute('r1');

    expect(result!.syncStatus, SyncStatus.pendingSync);
  });
}
