import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/task/transition_task_status_use_case.dart';
import 'package:notex/application/use_cases/timer/start_timer_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/repositories/task_repository.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/domain/value_objects/task_transition_outcome.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';
import 'package:notex/infrastructure/local/drift_time_entry_repository.dart';

/// Always throws — proves the task write can never block or fail the timer
/// write (design D1). A minimal fake, not a mock, mirroring the
/// `_UnusedXxx implements X { noSuchMethod ... }` convention established in
/// `delete_task_use_case_test.dart`.
class _ThrowingTaskRepository implements TaskRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('task repository failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTimeEntryRepository timeEntryRepository;
  late DriftTaskRepository taskRepository;
  late StartTimerUseCase useCase;

  Task blockedTask({
    String id = 't1',
    String? blockedReason = 'waiting on legal',
  }) {
    return Task(
      id: id,
      title: 'Blocked task',
      status: TaskStatus.blocked,
      blockedReason: blockedReason,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    timeEntryRepository = DriftTimeEntryRepository(db);
    taskRepository = DriftTaskRepository(db);
    useCase = StartTimerUseCase(
      timeEntryRepository,
      TransitionTaskStatusUseCase(taskRepository),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'starting a timer on a blocked task transitions it to doing and '
    'retains blockedReason',
    () async {
      await taskRepository.save(blockedTask());

      final result = await useCase.execute(id: 'e1', taskId: 't1');

      expect(result.taskTransition, TaskTransitionOutcome.applied);
      final updated = await taskRepository.getById('t1');
      expect(updated!.status, TaskStatus.doing);
      expect(updated.blockedReason, 'waiting on legal');
    },
  );

  test('the saved TimeEntry carries the taskId', () async {
    await taskRepository.save(blockedTask());

    final result = await useCase.execute(id: 'e1', taskId: 't1');

    expect(result.entry.taskId, 't1');
    final saved = await timeEntryRepository.getById('e1');
    expect(saved!.taskId, 't1');
  });

  test('a null taskId yields notApplicable and touches no task', () async {
    final result = await useCase.execute(id: 'e1');

    expect(result.taskTransition, TaskTransitionOutcome.notApplicable);
    expect(result.entry.taskId, isNull);
    expect(await taskRepository.getAll(), isEmpty);
  });

  test(
    'a throwing task repository returns failed, but the entry is still '
    'saved — the task write never blocks the timer write',
    () async {
      final failingUseCase = StartTimerUseCase(
        timeEntryRepository,
        TransitionTaskStatusUseCase(_ThrowingTaskRepository()),
      );

      final result = await failingUseCase.execute(id: 'e1', taskId: 't1');

      expect(result.taskTransition, TaskTransitionOutcome.failed);
      final saved = await timeEntryRepository.getById('e1');
      expect(saved, isNotNull);
      expect(saved!.taskId, 't1');
    },
  );

  test('a taskId that does not resolve to a task returns failed', () async {
    final result = await useCase.execute(id: 'e1', taskId: 'missing');

    expect(result.taskTransition, TaskTransitionOutcome.failed);
    final saved = await timeEntryRepository.getById('e1');
    expect(saved, isNotNull, reason: 'the timer entry is still saved');
  });

  test(
    'single-running-entry exclusivity holds when a timer linked to a task '
    'starts',
    () async {
      await taskRepository.save(blockedTask());
      await useCase.execute(id: 'e1', taskId: 't1', description: 'first');

      final result =
          await useCase.execute(id: 'e2', description: 'second');

      expect(result.taskTransition, TaskTransitionOutcome.notApplicable);
      final first = await timeEntryRepository.getById('e1');
      expect(first!.isRunning, isFalse);
      final running = await timeEntryRepository.getRunning();
      expect(running!.id, 'e2');
    },
  );
}
