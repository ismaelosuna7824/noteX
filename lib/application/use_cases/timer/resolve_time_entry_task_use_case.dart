import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';

/// Resolves the task behind a [TimeEntry.taskId], for the timer page's
/// "open the task this entry belongs to" affordance.
///
/// A time entry can outlive its task — tasks are soft-deleted, never
/// cascaded from a linked entry (mirrors [ResolveTaskNoteLinkUseCase]'s
/// degrade-rather-than-crash precedent for a task's linked notes), but
/// collapsed to a single nullable result here: unlike a linked note, this
/// caller offers no "in trash, restore?" step — only "open it" or "say
/// plainly it no longer exists" — so a missing id and a soft-deleted task
/// are the same outcome for this use case.
class ResolveTimeEntryTaskUseCase {
  final TaskRepository _repository;

  const ResolveTimeEntryTaskUseCase(this._repository);

  Future<Task?> execute(String taskId) async {
    final task = await _repository.getById(taskId);
    if (task == null || task.isDeleted) return null;
    return task;
  }
}
