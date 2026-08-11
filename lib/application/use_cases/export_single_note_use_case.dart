import '../../domain/repositories/note_export_sink.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/services/note_export_plan.dart';
import '../../infrastructure/content/note_content_format.dart';

/// Use case: write one note to a file the user chose.
///
/// Shares [NoteExportPlan]'s rendering with the whole-library export, so a
/// note saved on its own is byte-identical to the same note inside a full
/// export — front matter included.
class ExportSingleNoteUseCase {
  final NoteRepository _notes;
  final NoteExportSink _sink;

  /// File name taken from the save dialog.
  final String _fileName;

  const ExportSingleNoteUseCase(this._notes, this._sink, this._fileName);

  /// Writes the note, reporting false if it no longer exists.
  Future<bool> execute(String noteId) async {
    final note = await _notes.getById(noteId);
    if (note == null) return false;

    await _sink.write([
      NoteExportPlan.single(
        title: note.title,
        content: note.content,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        // Notes predating the v1.50 migration still hold Quill Delta JSON.
        toMarkdown: NoteContentFormat.ensureMarkdown,
        fileName: _fileName,
      ),
    ]);
    return true;
  }
}
