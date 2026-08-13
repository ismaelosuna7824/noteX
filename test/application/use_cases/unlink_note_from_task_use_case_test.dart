import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/task/unlink_note_from_task_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';

/// [UnlinkNoteFromTaskUseCase] removes exactly one note from a task's links,
/// leaving every other link untouched (decision
/// architecture/task-note-linking-model).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;
  late UnlinkNoteFromTaskUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTaskRepository(db);
    useCase = UnlinkNoteFromTaskUseCase(repository);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns null when the task id does not exist', () async {
    final result = await useCase.execute('missing', 'note-1');

    expect(result, isNull);
  });

  test('removes the only linked note, leaving an empty list', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteIds: const ['note-1'],
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.noteIds, isEmpty);
  });

  test('removes one note from the middle, leaving the others in order',
      () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteIds: const ['note-1', 'note-2', 'note-3'],
    ));

    final result = await useCase.execute('r1', 'note-2');

    expect(result!.noteIds, ['note-1', 'note-3']);
  });

  test('unlinking a note that is not linked is a no-op', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteIds: const ['note-1'],
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1', 'note-does-not-exist');

    expect(result!.noteIds, ['note-1']);
    expect(result.syncStatus, SyncStatus.synced);
  });

  test('never touches status', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteIds: const ['note-1'],
      status: TaskStatus.blocked,
      blockedReason: 'waiting on approval',
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.status, TaskStatus.blocked);
    expect(result.blockedReason, 'waiting on approval');
  });

  test('promotes a synced task to pendingSync', () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      noteIds: const ['note-1'],
      syncStatus: SyncStatus.synced,
    ));

    final result = await useCase.execute('r1', 'note-1');

    expect(result!.syncStatus, SyncStatus.pendingSync);
  });
}
