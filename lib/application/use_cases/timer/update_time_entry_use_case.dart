import '../../../domain/entities/time_entry.dart';
import '../../../domain/repositories/time_entry_repository.dart';

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
    final all = await _repository.getByDateRange(
      DateTime(2000),
      DateTime(2100),
    );
    final existing = all.cast<TimeEntry?>().firstWhere(
      (e) => e?.id == entryId,
      orElse: () => null,
    );
    if (existing == null) return null;

    final updated = existing.copyWith(
      description: description,
      projectId: projectId,
      startTime: startTime,
      endTime: endTime,
    );
    await _repository.save(updated);
    return updated;
  }
}

class _Unset {
  const _Unset();
}
