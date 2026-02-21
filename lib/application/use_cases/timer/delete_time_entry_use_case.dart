import '../../../domain/repositories/time_entry_repository.dart';

class DeleteTimeEntryUseCase {
  final TimeEntryRepository _repository;
  const DeleteTimeEntryUseCase(this._repository);

  Future<void> execute(String entryId) => _repository.delete(entryId);
}
