import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';

/// Use case: Retrieve notes.
///
/// Supports fetching all, by id, by date, and search.
class GetNotesUseCase {
  final NoteRepository _repository;

  const GetNotesUseCase(this._repository);

  /// Get all notes.
  Future<List<Note>> getAll() => _repository.getAll();

  /// Get a note by its [id].
  Future<Note?> getById(String id) => _repository.getById(id);

  /// Get the note for a specific [date].
  Future<Note?> getByDate(DateTime date) => _repository.getByDate(date);

  /// Search notes by [query].
  Future<List<Note>> search(String query) => _repository.search(query);

  /// Get total note count.
  Future<int> count() => _repository.count();
}
