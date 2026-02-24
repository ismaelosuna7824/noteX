import '../../../domain/entities/reminder.dart';
import '../../../domain/repositories/reminder_repository.dart';

/// Use case: Retrieve reminders.
class GetRemindersUseCase {
  final ReminderRepository _repository;

  const GetRemindersUseCase(this._repository);

  /// Get all non-deleted reminders.
  Future<List<Reminder>> getAll() => _repository.getAll();

  /// Get pending (uncompleted) reminders up to and including [upToDate].
  Future<List<Reminder>> getPending(DateTime upToDate) =>
      _repository.getPending(upToDate);
}
