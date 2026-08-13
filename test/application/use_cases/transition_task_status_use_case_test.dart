import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/task/transition_task_status_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';

/// [TransitionTaskStatusUseCase] replaces `CompleteTaskUseCase` (design D3 —
/// it is the sole producer of transition writes). These tests replay the
/// same behavior [CompleteTaskUseCase] used to cover under its new,
/// status-based shape.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;
  late TransitionTaskStatusUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTaskRepository(db);
    useCase = TransitionTaskStatusUseCase(repository);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns null when the task id does not exist', () async {
    final result = await useCase.execute('missing', TaskStatus.done);

    expect(result, isNull);
  });

  test('transitions an existing task and persists it', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1', TaskStatus.done);

    expect(result, isNotNull);
    expect(result!.status, TaskStatus.done);
    expect(result.isDone, isTrue);
    expect(result.completedAt, isNotNull);

    final persisted = await repository.getById('r1');
    expect(persisted!.status, TaskStatus.done);
    expect(persisted.completedAt, isNotNull);
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

    final result = await useCase.execute('r1', TaskStatus.done);

    expect(result!.syncStatus, SyncStatus.localOnly);
  });

  test('promotes a synced task to pendingSync on transition', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1', TaskStatus.done);

    expect(result!.syncStatus, SyncStatus.pendingSync);
  });

  test('retains blockedReason when moving from blocked to doing', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      status: TaskStatus.blocked,
      blockedReason: 'waiting on approval',
    ));

    final result = await useCase.execute('r1', TaskStatus.doing);

    expect(result!.status, TaskStatus.doing);
    expect(result.blockedReason, 'waiting on approval');
  });

  test('sets statusPendingPush so the transition is pushed on next sync',
      () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1', TaskStatus.done);

    expect(result!.statusPendingPush, isTrue);
  });

  // Slice 2 task 2.12 — re-verification. The Kanban board can drag a `done`
  // card to another column, un-completing it; before slice 2 the only path
  // to `isDone == false` was disabled once a task was completed
  // (task_page.dart's checkbox guard). This use case remains the SOLE
  // producer of that transition regardless of caller (board drag, flat-list
  // checkbox, or any future path) — see design's row-5 invariant.
  test('un-completing (done -> todo) writes status and is_completed '
      'together, never one without the other', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      status: TaskStatus.done,
      completedAt: DateTime(2026, 3, 3),
      syncStatus: SyncStatus.synced,
      statusPendingPush: false,
    ));

    final result = await useCase.execute('r1', TaskStatus.todo);

    expect(result!.status, TaskStatus.todo);
    expect(result.isDone, isFalse);
    expect(result.completedAt, isNull);
    // The quartet travels as a unit (D10 R1) — this is what keeps row 5 of
    // the M8 contract table safe: no shipped path can author
    // is_completed=false without also authoring status.
    expect(result.statusPendingPush, isTrue);

    final persisted = await repository.getById('r1');
    expect(persisted!.status, TaskStatus.todo);
    expect(persisted.isDone, isFalse);
  });
}
