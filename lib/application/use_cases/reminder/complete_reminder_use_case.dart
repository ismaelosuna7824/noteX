import '../../../domain/entities/reminder.dart';
import '../../../domain/repositories/reminder_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: Mark a reminder as completed.
class CompleteReminderUseCase {
  final ReminderRepository _repository;

  const CompleteReminderUseCase(this._repository);

  Future<Reminder?> execute(String reminderId) async {
    final existing = await _repository.getById(reminderId);
    if (existing == null) return null;

    // Preserve localOnly status for unauthenticated users
    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.copyWith(
      isCompleted: true,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: newSyncStatus,
    );

    await _repository.save(updated);
    return updated;
  }
}
