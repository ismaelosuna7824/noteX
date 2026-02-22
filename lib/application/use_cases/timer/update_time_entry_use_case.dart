import '../../../domain/entities/time_entry.dart';
import '../../../domain/repositories/time_entry_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

class UpdateTimeEntryUseCase {
  final TimeEntryRepository _repository;
  const UpdateTimeEntryUseCase(this._repository);

  Future<TimeEntry?> execute({
    required String entryId,
    String? description,
    Object? projectId = const _Unset(),
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final existing = await _repository.getById(entryId);
    if (existing == null) return null;

    final updated = existing.copyWith(
      description: description,
      projectId: projectId,
      startTime: startTime,
      endTime: endTime is _Unset ? null : endTime,
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
    await _repository.save(updated);
    return updated;
  }
}

class _Unset {
  const _Unset();
}
