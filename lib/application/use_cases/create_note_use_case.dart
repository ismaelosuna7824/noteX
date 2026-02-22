import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';

/// Use case: Create a new note.
///
/// Handles daily auto-creation logic — if a note for today doesn't exist,
/// creates one automatically.
class CreateNoteUseCase {
  final NoteRepository _repository;

  const CreateNoteUseCase(this._repository);

  /// Creates a new note with the given [id].
  /// If [ensureDaily] is true, first checks if a note for today exists.
  Future<Note> execute({
    required String id,
    String? title,
    String? backgroundImage,
    String? themeId,
    bool ensureDaily = false,
  }) async {
    if (ensureDaily) {
      final existing = await _repository.getByDate(DateTime.now());
      if (existing != null) return existing;
    }

    final note = Note.createDaily(
      id: id,
      backgroundImage: backgroundImage,
      themeId: themeId,
    ).copyWith(
      title: title,
    );

    await _repository.save(note);
    return note;
  }
}
