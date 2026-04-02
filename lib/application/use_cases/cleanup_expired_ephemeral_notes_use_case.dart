import '../../domain/repositories/note_repository.dart';

/// Use case: Remove expired ephemeral (quick) notes.
///
/// Ephemeral notes are local-only and auto-delete after 24 hours.
/// Uses hard-delete so they bypass trash completely.
class CleanupExpiredEphemeralNotesUseCase {
  final NoteRepository _repository;

  const CleanupExpiredEphemeralNotesUseCase(this._repository);

  /// Hard-deletes all expired ephemeral notes.
  /// Returns the number of notes removed.
  Future<int> execute() async {
    final expired = await _repository.getExpiredEphemeral();
    for (final note in expired) {
      await _repository.delete(note.id);
    }
    return expired.length;
  }
}
