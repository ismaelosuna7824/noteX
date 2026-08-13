import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/task.dart';
import '../../application/use_cases/task/create_task_use_case.dart';
import '../../application/use_cases/task/get_tasks_use_case.dart';
import '../../application/use_cases/task/complete_task_use_case.dart';
import '../../application/use_cases/task/delete_task_use_case.dart';

/// Presentation state for the Reminder feature.
///
/// Manages all reminders and the pending-today subset used by the Home card.
class ReminderState extends ChangeNotifier {
  final CreateTaskUseCase _createReminder;
  final GetTasksUseCase _getReminders;
  final CompleteTaskUseCase _completeReminder;
  final DeleteTaskUseCase _deleteReminder;

  List<Task> _reminders = [];
  List<Task> _pendingToday = [];

  ReminderState({
    required CreateTaskUseCase createReminder,
    required GetTasksUseCase getReminders,
    required CompleteTaskUseCase completeReminder,
    required DeleteTaskUseCase deleteReminder,
  })  : _createReminder = createReminder,
        _getReminders = getReminders,
        _completeReminder = completeReminder,
        _deleteReminder = deleteReminder;

  // Getters
  List<Task> get reminders => _reminders;
  List<Task> get pendingToday => _pendingToday;
  bool get hasPendingToday => _pendingToday.isNotEmpty;

  /// Load all reminders and the pending-today list.
  Future<void> initialize() async {
    _reminders = await _getReminders.getAll();
    _pendingToday = await _getReminders.getPending(DateTime.now());
    notifyListeners();
  }

  /// Refresh both lists from the database.
  Future<void> refreshReminders() async {
    _reminders = await _getReminders.getAll();
    _pendingToday = await _getReminders.getPending(DateTime.now());
    notifyListeners();
  }

  /// Create a new reminder with a title and scheduled date.
  Future<Task> createReminder({
    required String title,
    required DateTime scheduledDate,
  }) async {
    final reminder = await _createReminder.execute(
      id: const Uuid().v4(),
      title: title,
      scheduledDate: scheduledDate,
    );
    await refreshReminders();
    return reminder;
  }

  /// Mark a reminder as completed.
  Future<void> completeReminder(String id) async {
    await _completeReminder.execute(id);
    await refreshReminders();
  }

  /// Soft-delete a reminder.
  Future<void> deleteReminder(String id) async {
    await _deleteReminder.execute(id);
    await refreshReminders();
  }
}
