import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';

/// Use case: Create a new task.
class CreateTaskUseCase {
  final TaskRepository _repository;

  const CreateTaskUseCase(this._repository);

  Future<Task> execute({
    required String id,
    required String title,
    required DateTime scheduledDate,
  }) async {
    final task = Task.create(
      id: id,
      title: title,
      scheduledDate: scheduledDate,
    );
    await _repository.save(task);
    return task;
  }
}
