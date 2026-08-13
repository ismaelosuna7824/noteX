import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/task/update_task_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';

/// [UpdateTaskUseCase] is new in Phase 1.4 — it is the only place
/// user-authored `blockedReason` text is cleared, and it must never touch
/// `status` or emit the status quartet on sync (design D3/D10).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;
  late UpdateTaskUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTaskRepository(db);
    useCase = UpdateTaskUseCase(repository);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns null when the task id does not exist', () async {
    final result = await useCase.execute('missing', title: 'New title');

    expect(result, isNull);
  });

  test('updates title, description and scheduledDate', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute(
      'r1',
      title: 'Buy oat milk',
      description: 'Get the barista blend',
      scheduledDate: DateTime(2026, 3, 10),
    );

    expect(result!.title, 'Buy oat milk');
    expect(result.description, 'Get the barista blend');
    expect(result.scheduledDate, DateTime(2026, 3, 10));
  });

  test('preserves scheduledDate when omitted', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    final result = await useCase.execute('r1', title: 'Buy oat milk');

    expect(result!.scheduledDate, DateTime(2026, 3, 4));
  });

  test('clears scheduledDate — moves to backlog — when explicitly passed '
      'null', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    final result = await useCase.execute('r1', scheduledDate: null);

    expect(result!.scheduledDate, isNull);
  });

  test('sets noteId when passed a value', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    final result = await useCase.execute('r1', noteId: 'note-1');

    expect(result!.noteId, 'note-1');
  });

  test('clears noteId when explicitly passed null', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteId: 'note-1',
    ));

    final result = await useCase.execute('r1', noteId: null);

    expect(result!.noteId, isNull);
  });

  test('preserves noteId when omitted', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteId: 'note-1',
    ));

    final result = await useCase.execute('r1', title: 'Buy oat milk');

    expect(result!.noteId, 'note-1');
  });

  test('clears blockedReason only when explicitly passed null', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      status: TaskStatus.blocked,
      blockedReason: 'waiting on approval',
    ));

    final preserved = await useCase.execute('r1', title: 'still blocked');
    expect(preserved!.blockedReason, 'waiting on approval');

    final cleared = await useCase.execute('r1', blockedReason: null);
    expect(cleared!.blockedReason, isNull);
  });

  test('never touches status', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      status: TaskStatus.doing,
    ));

    final result = await useCase.execute('r1', title: 'Buy oat milk');

    expect(result!.status, TaskStatus.doing);
  });

  test('does not set statusPendingPush — must not emit the status quartet',
      () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      statusPendingPush: false,
    ));

    final result = await useCase.execute('r1', title: 'Buy oat milk');

    expect(result!.statusPendingPush, isFalse);
  });

  test('preserves localOnly sync status for unauthenticated users', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.localOnly,
    ));

    final result = await useCase.execute('r1', title: 'Buy oat milk');

    expect(result!.syncStatus, SyncStatus.localOnly);
  });

  test('promotes a synced task to pendingSync', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1', title: 'Buy oat milk');

    expect(result!.syncStatus, SyncStatus.pendingSync);
  });
}
