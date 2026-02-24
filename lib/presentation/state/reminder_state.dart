import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/reminder.dart';
import '../../application/use_cases/reminder/create_reminder_use_case.dart';
import '../../application/use_cases/reminder/get_reminders_use_case.dart';
import '../../application/use_cases/reminder/complete_reminder_use_case.dart';
import '../../application/use_cases/reminder/delete_reminder_use_case.dart';

/// Presentation state for the Reminder feature.
///
/// Manages all reminders and the pending-today subset used by the Home card.
class ReminderState extends ChangeNotifier {
  final CreateReminderUseCase _createReminder;
  final GetRemindersUseCase _getReminders;
  final CompleteReminderUseCase _completeReminder;
  final DeleteReminderUseCase _deleteReminder;

  List<Reminder> _reminders = [];
  List<Reminder> _pendingToday = [];

  ReminderState({
    required CreateReminderUseCase createReminder,
    required GetRemindersUseCase getReminders,
    required CompleteReminderUseCase completeReminder,
    required DeleteReminderUseCase deleteReminder,
  })  : _createReminder = createReminder,
        _getReminders = getReminders,
        _completeReminder = completeReminder,
        _deleteReminder = deleteReminder;

  // Getters
  List<Reminder> get reminders => _reminders;
  List<Reminder> get pendingToday => _pendingToday;
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
  Future<Reminder> createReminder({
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
