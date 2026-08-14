import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/task/link_note_to_task_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';

/// [LinkNoteToTaskUseCase] appends a note to a task's links (decision
/// architecture/task-note-linking-model — a task carries N notes, its
/// accumulating "mini documentation", not a single link).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;
  late LinkNoteToTaskUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTaskRepository(db);
    useCase = LinkNoteToTaskUseCase(repository);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns null when the task id does not exist', () async {
    final result = await useCase.execute('missing', 'note-1');

    expect(result, isNull);
  });

  test('appends the first note to an empty list', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.noteIds, ['note-1']);
  });

  test('appends a second note without replacing the first', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteIds: const ['note-1'],
    ));

    final result = await useCase.execute('r1', 'note-2');

    expect(result!.noteIds, ['note-1', 'note-2']);
  });

  test('linking an already-linked note is a no-op — no duplicate entry',
      () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteIds: const ['note-1'],
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.noteIds, ['note-1']);
    // No-op write: sync status must not have been promoted, proving the
    // repository was never re-saved for this call.
    expect(result.syncStatus, SyncStatus.synced);
  });

  test('never touches status', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      status: TaskStatus.doing,
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.status, TaskStatus.doing);
  });

  test('does not set statusPendingPush — must not emit the status quartet',
      () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
      statusPendingPush: false,
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.statusPendingPush, isFalse);
  });

  test('promotes a synced task to pendingSync', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.syncStatus, SyncStatus.pendingSync);
  });

  test('preserves localOnly sync status for unauthenticated users', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      syncStatus: SyncStatus.localOnly,
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.syncStatus, SyncStatus.localOnly);
  });
}
