import '../../../domain/entities/time_entry.dart';
import '../../../domain/repositories/time_entry_repository.dart';

/// Stops any currently running entry, then starts a new one.
class StartTimerUseCase {
  final TimeEntryRepository _repository;
  const StartTimerUseCase(this._repository);

  Future<TimeEntry> execute({
    required String id,
    String description = '',
    String? projectId,
  }) async {
    // Stop any running entry first
    final running = await _repository.getRunning();
    if (running != null) {
      await _repository.save(running.stop());
    }

    final now = DateTime.now();
    final entry = TimeEntry(
      id: id,
      description: description,
      projectId: projectId,
      startTime: now,
      updatedAt: now,
    );
    await _repository.save(entry);
    return entry;
  }
}
