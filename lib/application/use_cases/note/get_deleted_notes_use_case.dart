import '../../../domain/entities/note.dart';
import '../../../domain/repositories/note_repository.dart';

/// Use case: Retrieve all soft-deleted notes (trash).
class GetDeletedNotesUseCase {
  final NoteRepository _repository;

  const GetDeletedNotesUseCase(this._repository);

  Future<List<Note>> execute() => _repository.getDeleted();
}
