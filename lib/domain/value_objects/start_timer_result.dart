import '../entities/time_entry.dart';
import 'task_transition_outcome.dart';

/// Result of `StartTimerUseCase.execute`.
///
/// Always carries the saved [entry] — the timer write always succeeds
/// unconditionally (design D1). [taskTransition] carries the outcome of the
/// best-effort task-status transition attempted when the timer is linked to
/// a task; a failure there is surfaced here rather than thrown or silently
/// swallowed, so the caller can attribute it back to the user's gesture.
class StartTimerResult {
  final TimeEntry entry;
  final TaskTransitionOutcome taskTransition;

  const StartTimerResult({required this.entry, required this.taskTransition});
}
