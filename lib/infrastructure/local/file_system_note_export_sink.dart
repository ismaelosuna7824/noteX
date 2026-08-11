import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/repositories/note_export_sink.dart';
import '../../domain/services/note_export_plan.dart';

/// Infrastructure adapter: writes an export to a directory on disk.
class FileSystemNoteExportSink implements NoteExportSink {
  /// Directory the export is written into. Created if it does not exist.
  final String rootPath;

  const FileSystemNoteExportSink(this.rootPath);

  @override
  Future<void> write(List<ExportEntry> entries) async {
    final root = Directory(rootPath);
    await root.create(recursive: true);
    final rootAbsolute = p.normalize(root.absolute.path);

    for (final entry in entries) {
      // Entry paths are always `/`-separated; rebuild them with the platform
      // separator so this works on Windows too.
      final target = p.normalize(
        p.joinAll([rootAbsolute, ...entry.path.split('/')]),
      );

      // NoteExportPlan already makes it impossible for a title to become a
      // path segment, but the port promises the sink never writes outside its
      // root, and that promise should not depend on a caller's diligence.
      if (!p.isWithin(rootAbsolute, target)) continue;

      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.content);
    }
  }
}
