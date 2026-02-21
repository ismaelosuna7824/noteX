import '../../../domain/entities/time_entry.dart';
import '../../../domain/repositories/time_entry_repository.dart';

class GetTimeEntriesUseCase {
  final TimeEntryRepository _repository;
  const GetTimeEntriesUseCase(this._repository);

  Future<TimeEntry?> getRunning() => _repository.getRunning();

  Future<List<TimeEntry>> getByDateRange(DateTime from, DateTime to) =>
      _repository.getByDateRange(from, to);
}
