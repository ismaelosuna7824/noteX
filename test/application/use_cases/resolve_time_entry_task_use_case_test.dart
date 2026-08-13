import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/timer/resolve_time_entry_task_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';

/// [ResolveTimeEntryTaskUseCase] powers the timer page's "open the task
/// this entry belongs to" affordance. A time entry can outlive its task
/// (tasks are soft-deleted, never cascaded from a linked entry) — this
/// use case collapses "never existed" and "soft-deleted" into a single
/// `null` result, so the caller degrades identically either way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;
  late ResolveTimeEntryTaskUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTaskRepository(db);
    useCase = ResolveTimeEntryTaskUseCase(repository);
  });

  tearDown(() async {
    await db.close();
  });

  test('returns the task when it exists and is not deleted', () async {
    final task = Task.create(id: 't1', title: 'Write report');
    await repository.save(task);

    final result = await useCase.execute('t1');

    expect(result, isNotNull);
    expect(result!.id, 't1');
    expect(result.title, 'Write report');
  });

  test('returns null when no task exists for the id — a time entry that '
      'never carried a real taskId, or one that has since been purged',
      () async {
    final result = await useCase.execute('does-not-exist');

    expect(result, isNull);
  });

  test('returns null for a soft-deleted task — same outcome as a missing '
      'one, since this affordance offers no restore step', () async {
    final task = Task.create(id: 't1', title: 'Old task').markDeleted();
    await repository.save(task);

    final result = await useCase.execute('t1');

    expect(result, isNull);
    final stillThere = await repository.getById('t1');
    expect(
      stillThere,
      isNotNull,
      reason: 'resolving must never cascade or mutate the task',
    );
  });
}
