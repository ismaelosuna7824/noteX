import '../../domain/repositories/markdown_file_repository.dart';
import '../../domain/repositories/note_export_sink.dart';
import '../../domain/services/note_export_plan.dart';

/// Use case: write one Markdown file to a location the user chose.
///
/// The sibling of [ExportSingleNoteUseCase] for the other library. Both render
/// through [NoteExportPlan.single], so the same content exports identically
/// whichever side of the app it happens to live on.
class ExportMarkdownFileUseCase {
  final MarkdownFileRepository _files;
  final NoteExportSink _sink;

  /// File name taken from the save dialog.
  final String _fileName;

  const ExportMarkdownFileUseCase(this._files, this._sink, this._fileName);

  /// Writes the file, reporting false if it no longer exists.
  Future<bool> execute(String fileId) async {
    final file = await _files.getById(fileId);
    if (file == null) return false;

    await _sink.write([
      NoteExportPlan.single(
        title: file.title,
        content: file.content,
        createdAt: file.createdAt,
        updatedAt: file.updatedAt,
        // Markdown files are always stored as Markdown — unlike notes, none
        // of them predate the v1.50 migration — so no conversion is needed.
        toMarkdown: (content) => content,
        fileName: _fileName,
      ),
    ]);
    return true;
  }
}
