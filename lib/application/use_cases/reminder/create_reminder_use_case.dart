import '../../../domain/entities/reminder.dart';
import '../../../domain/repositories/reminder_repository.dart';

/// Use case: Create a new reminder.
class CreateReminderUseCase {
  final ReminderRepository _repository;

  const CreateReminderUseCase(this._repository);

  Future<Reminder> execute({
    required String id,
    required String title,
    required DateTime scheduledDate,
  }) async {
    final reminder = Reminder.create(
      id: id,
      title: title,
      scheduledDate: scheduledDate,
    );
    await _repository.save(reminder);
    return reminder;
  }
}
