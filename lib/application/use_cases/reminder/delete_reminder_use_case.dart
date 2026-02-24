import '../../../domain/repositories/reminder_repository.dart';
import '../../services/sync_engine.dart';

/// Use case: Soft-delete a reminder, then trigger sync.
class DeleteReminderUseCase {
  final ReminderRepository _repository;
  final SyncEngine _syncEngine;

  const DeleteReminderUseCase(this._repository, this._syncEngine);

  Future<void> execute(String reminderId) async {
    final existing = await _repository.getById(reminderId);
    if (existing != null) {
      await _repository.save(existing.markDeleted());
    }
    await _syncEngine.syncIfAuthenticated();
  }
}
