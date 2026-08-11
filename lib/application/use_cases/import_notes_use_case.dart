import '../../domain/entities/note.dart';
import '../../domain/entities/note_project.dart';
import '../../domain/repositories/note_import_source.dart';
import '../../domain/repositories/note_project_repository.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/services/markdown_import_parser.dart';

/// What an import produced.
class ImportSummary {
  final int notesCreated;
  final int foldersCreated;

  const ImportSummary({
    required this.notesCreated,
    required this.foldersCreated,
  });

  bool get isEmpty => notesCreated == 0;
}

/// Use case: create notes from Markdown files.
///
/// Every file becomes a NEW note. Imports are deliberately not idempotent:
/// nothing in an exported file identifies which note it came from, so the
/// importer cannot tell a re-import from a fresh one and does not pretend to.
/// Importing the same folder twice gives you the notes twice.
///
/// Folders are matched by name before being created, so importing into a
/// library that already has a `daily notes` folder files the notes there
/// instead of creating a second one.
class ImportNotesUseCase {
  final NoteRepository _notes;
  final NoteProjectRepository _projects;
  final NoteImportSource _source;
  final String Function() _newId;

  const ImportNotesUseCase(
    this._notes,
    this._projects,
    this._source,
    this._newId,
  );

  /// Reads the source and writes what it finds.
  ///
  /// [folderColorValue] paints any folder this import has to create.
  Future<ImportSummary> execute({required int folderColorValue}) async {
    final files = await _source.read();
    if (files.isEmpty) {
      return const ImportSummary(notesCreated: 0, foldersCreated: 0);
    }

    // Existing folders, keyed the way lookups happen: within a parent, by
    // case-insensitive name. Matches how a user thinks about folder names.
    final byParentAndName = <String, NoteProject>{
      for (final project in await _projects.getAll())
        if (project.deletedAt == null)
          _folderKey(project.parentId, project.name): project,
    };

    var notesCreated = 0;
    var foldersCreated = 0;

    for (final file in files) {
      final parsed = MarkdownImportParser.parse(
        relativePath: file.relativePath,
        raw: file.content,
      );

      String? parentId;
      for (final folderName in parsed.folders) {
        final key = _folderKey(parentId, folderName);
        var folder = byParentAndName[key];

        if (folder == null) {
          folder = NoteProject.create(
            id: _newId(),
            name: folderName,
            colorValue: folderColorValue,
            parentId: parentId,
          );
          await _projects.save(folder);
          byParentAndName[key] = folder;
          foldersCreated++;
        }

        parentId = folder.id;
      }

      // Dates fall back forward: a file with no front matter is new to this
      // library, so "now" is the honest answer.
      final createdAt = parsed.createdAt ?? DateTime.now();

      await _notes.save(Note(
        id: _newId(),
        title: parsed.title,
        content: parsed.content,
        createdAt: createdAt,
        updatedAt: parsed.updatedAt ?? createdAt,
        projectId: parentId,
      ));
      notesCreated++;
    }

    return ImportSummary(
      notesCreated: notesCreated,
      foldersCreated: foldersCreated,
    );
  }

  static String _folderKey(String? parentId, String name) =>
      '${parentId ?? ''}/${name.toLowerCase()}';
}
