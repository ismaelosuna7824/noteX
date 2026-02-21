import '../../../domain/entities/time_entry.dart';
import '../../../domain/repositories/time_entry_repository.dart';

class StopTimerUseCase {
  final TimeEntryRepository _repository;
  const StopTimerUseCase(this._repository);

  Future<TimeEntry?> execute(String entryId) async {
    final running = await _repository.getRunning();
    if (running == null || running.id != entryId) return null;

    final stopped = running.stop();
    await _repository.save(stopped);
    return stopped;
  }
}
