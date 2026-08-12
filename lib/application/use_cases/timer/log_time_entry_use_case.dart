import '../../../domain/entities/time_entry.dart';
import '../../../domain/repositories/time_entry_repository.dart';

/// Records work that already happened.
///
/// Deliberately not [StartTimerUseCase] with an end bolted on. Starting a timer
/// stops whatever was running, because two clocks cannot both be now — but
/// logging Tuesday's forgotten hour has nothing to do with the timer ticking
/// on Wednesday, and stopping it would punish someone for filling in a gap.
class LogTimeEntryUseCase {
  final TimeEntryRepository _repository;
  const LogTimeEntryUseCase(this._repository);

  Future<TimeEntry> execute({
    required String id,
    required DateTime startTime,
    required DateTime endTime,
    String description = '',
    String? projectId,
  }) async {
    // An end before its start is not a diary entry, it is a bug waiting to be
    // divided by. Ordering here rather than trusting the caller keeps every
    // stored entry summable.
    final start = endTime.isBefore(startTime) ? endTime : startTime;
    final end = endTime.isBefore(startTime) ? startTime : endTime;

    final entry = TimeEntry(
      id: id,
      description: description,
      projectId: projectId,
      startTime: start,
      endTime: end,
      updatedAt: DateTime.now(),
    );

    await _repository.save(entry);
    return entry;
  }
}
