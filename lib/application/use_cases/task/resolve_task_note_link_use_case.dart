import '../../../domain/repositories/note_repository.dart';
import '../../../domain/value_objects/note_link_resolution.dart';

/// Resolves a task's linked note into one of three affordance states
/// (design D9, spec capability `task-note-linking`): found and live → open
/// it; found and soft-deleted → "in trash, restore?" (link preserved);
/// not found → "note no longer exists", offer to clear the link.
///
/// Always goes through [NoteRepository.getById], which does NOT filter
/// `deletedAt` — resolving through a deleted-filtered in-memory list would
/// collapse "in trash" (reversible) and "permanently gone" (not) into one
/// indistinguishable state.
class ResolveTaskNoteLinkUseCase {
  final NoteRepository _repository;

  const ResolveTaskNoteLinkUseCase(this._repository);

  Future<NoteLinkResolution> execute(String noteId) async {
    final note = await _repository.getById(noteId);
    if (note == null) {
      return const NoteLinkResolution(NoteLinkStatus.missing, null);
    }
    return NoteLinkResolution(
      note.isDeleted ? NoteLinkStatus.inTrash : NoteLinkStatus.found,
      note,
    );
  }
}
