import '../../domain/repositories/note_repository.dart';
import '../../domain/services/title_generation_service.dart';
import 'update_note_use_case.dart';

/// Use case: Generate a title for a note using an external API.
///
/// Sends the note content summary and updates the note with the generated title.
class GenerateTitleUseCase {
  final NoteRepository _repository;
  final TitleGenerationService _titleService;
  final UpdateNoteUseCase _updateNote;

  const GenerateTitleUseCase(
    this._repository,
    this._titleService,
    this._updateNote,
  );

  /// Generate and apply a title for the note with [noteId].
  Future<String?> execute(String noteId) async {
    final note = await _repository.getById(noteId);
    if (note == null) return null;

    // Extract a plain-text summary from the content
    final summary = _extractSummary(note.content);
    if (summary.isEmpty) return null;

    final generatedTitle = await _titleService.generateTitle(summary);

    await _updateNote.execute(
      noteId: noteId,
      title: generatedTitle,
    );

    return generatedTitle;
  }

  /// Extracts a plain-text summary from Quill Delta JSON content.
  String _extractSummary(String deltaJson) {
    // Simple extraction: strip JSON markup to get raw text
    // In production, parse the Delta properly
    final text = deltaJson
        .replaceAll(RegExp(r'[\[\]{}"\\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Return first 500 characters as summary
    return text.length > 500 ? text.substring(0, 500) : text;
  }
}
