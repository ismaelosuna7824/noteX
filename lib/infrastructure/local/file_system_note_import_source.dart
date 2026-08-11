import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/repositories/note_import_source.dart';
import '../../domain/services/markdown_import_parser.dart';

/// Infrastructure adapter: reads Markdown files from a directory tree.
class FileSystemNoteImportSource implements NoteImportSource {
  /// Directory to walk. Subdirectories are included.
  final String rootPath;

  const FileSystemNoteImportSource(this.rootPath);

  @override
  Future<List<ImportFile>> read() async {
    final root = Directory(rootPath);
    if (!root.existsSync()) return const [];

    final files = <ImportFile>[];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      // Normalised to `/` so the domain sees one path shape on every platform.
      final relative = p.relative(entity.path, from: root.path).split(p.separator).join('/');
      if (!MarkdownImportParser.accepts(relative)) continue;

      try {
        files.add(ImportFile(
          relativePath: relative,
          content: await entity.readAsString(),
        ));
      } on FileSystemException {
        // Unreadable file — skip it rather than abandoning the whole import.
        continue;
      }
    }

    // Directory listing order is filesystem-dependent; sorting keeps an import
    // reproducible and makes the resulting note order predictable.
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return files;
  }
}
