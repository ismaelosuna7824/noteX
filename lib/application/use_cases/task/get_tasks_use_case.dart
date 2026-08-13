import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';

/// Use case: Retrieve tasks.
class GetTasksUseCase {
  final TaskRepository _repository;

  const GetTasksUseCase(this._repository);

  /// Get all non-deleted tasks.
  Future<List<Task>> getAll() => _repository.getAll();

  /// Get pending (uncompleted) tasks up to and including [upToDate].
  Future<List<Task>> getPending(DateTime upToDate) =>
      _repository.getPending(upToDate);

  /// Get all non-deleted, blocked tasks.
  Future<List<Task>> getBlocked() => _repository.getBlocked();

  /// Get non-deleted, done tasks scheduled on [day].
  Future<List<Task>> getCompletedOn(DateTime day) =>
      _repository.getCompletedOn(day);
}
