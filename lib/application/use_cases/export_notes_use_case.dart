import '../../domain/repositories/note_export_sink.dart';
import '../../domain/repositories/note_project_repository.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/services/note_export_plan.dart';
import '../../infrastructure/content/note_content_format.dart';

/// What an export produced.
class ExportSummary {
  /// Number of note files written.
  final int fileCount;

  const ExportSummary({required this.fileCount});

  bool get isEmpty => fileCount == 0;
}

/// Use case: export every visible note as a Markdown file.
///
/// Reads the library, plans the file tree with [NoteExportPlan], and hands the
/// result to a [NoteExportSink]. All the decisions live in the plan; this only
/// gathers input and delegates output, which is why there is nothing here that
/// needs a filesystem to reason about.
class ExportNotesUseCase {
  final NoteRepository _notes;
  final NoteProjectRepository _projects;
  final NoteExportSink _sink;

  const ExportNotesUseCase(this._notes, this._projects, this._sink);

  /// Writes the whole library and reports how many files it produced.
  Future<ExportSummary> execute() async {
    final entries = NoteExportPlan.build(
      notes: await _notes.getAll(),
      projects: await _projects.getAll(),
      // Notes written before the v1.50 migration still hold Quill Delta JSON.
      // Without this they would export as unreadable JSON rather than prose.
      toMarkdown: NoteContentFormat.ensureMarkdown,
    );

    if (entries.isNotEmpty) await _sink.write(entries);

    return ExportSummary(fileCount: entries.length);
  }
}
