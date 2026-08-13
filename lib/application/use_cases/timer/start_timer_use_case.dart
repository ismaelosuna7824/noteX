import '../../../domain/entities/time_entry.dart';
import '../../../domain/repositories/time_entry_repository.dart';
import '../../../domain/value_objects/start_timer_result.dart';
import '../../../domain/value_objects/task_status.dart';
import '../../../domain/value_objects/task_transition_outcome.dart';
import '../task/transition_task_status_use_case.dart';

/// Stops any currently running entry, then starts a new one.
///
/// When [taskId] is provided, also transitions that task to `doing` —
/// including from `blocked`, with no confirmation — as a side effect
/// (design D1). The transition goes through [TransitionTaskStatusUseCase],
/// the sole producer of transition writes (design D3/D6), so the R1
/// push-payload contract holds; it is never written directly here.
///
/// That task write is best-effort: it can never block, delay or roll back
/// the timer write. The [TimeEntry] is saved unconditionally first, and the
/// task-transition outcome is surfaced in [StartTimerResult.taskTransition]
/// rather than thrown or silently swallowed.
class StartTimerUseCase {
  final TimeEntryRepository _repository;
  final TransitionTaskStatusUseCase _transitionTaskStatus;

  const StartTimerUseCase(this._repository, this._transitionTaskStatus);

  Future<StartTimerResult> execute({
    required String id,
    String description = '',
    String? projectId,
    String? taskId,
  }) async {
    // Stop any running entry first
    final running = await _repository.getRunning();
    if (running != null) {
      await _repository.save(running.stop());
    }

    final now = DateTime.now();
    final entry = TimeEntry(
      id: id,
      description: description,
      projectId: projectId,
      taskId: taskId,
      startTime: now,
      updatedAt: now,
    );
    // The timer write must never be blocked, delayed or rolled back by the
    // task write (design D1) — save it unconditionally, before attempting
    // any task transition.
    await _repository.save(entry);

    if (taskId == null) {
      return StartTimerResult(
        entry: entry,
        taskTransition: TaskTransitionOutcome.notApplicable,
      );
    }

    try {
      final updated =
          await _transitionTaskStatus.execute(taskId, TaskStatus.doing);
      return StartTimerResult(
        entry: entry,
        taskTransition: updated != null
            ? TaskTransitionOutcome.applied
            : TaskTransitionOutcome.failed,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[StartTimerUseCase] task transition failed: $e');
      return StartTimerResult(
        entry: entry,
        taskTransition: TaskTransitionOutcome.failed,
      );
    }
  }
}
