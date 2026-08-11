import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/services/note_export_plan.dart';
import 'package:notex/infrastructure/local/file_system_note_export_sink.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('notex_export_test');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  String read(String relative) =>
      File(p.join(root.path, p.joinAll(relative.split('/')))).readAsStringSync();

  test('writes a file at the root', () async {
    await FileSystemNoteExportSink(root.path).write([
      const ExportEntry(path: 'Ideas.md', content: 'hello'),
    ]);

    expect(read('Ideas.md'), 'hello');
  });

  test('creates nested folders as the paths imply', () async {
    await FileSystemNoteExportSink(root.path).write([
      const ExportEntry(path: 'Work/Q3/Deep.md', content: 'nested'),
    ]);

    expect(read('Work/Q3/Deep.md'), 'nested');
  });

  test('creates the export directory when it does not exist yet', () async {
    final target = p.join(root.path, 'brand', 'new');
    await FileSystemNoteExportSink(target).write([
      const ExportEntry(path: 'A.md', content: 'x'),
    ]);

    expect(File(p.join(target, 'A.md')).existsSync(), isTrue);
  });

  test('refuses to write outside its own root', () async {
    final outside = p.join(root.path, 'escaped.md');

    await FileSystemNoteExportSink(p.join(root.path, 'inner')).write([
      const ExportEntry(path: '../escaped.md', content: 'nope'),
      const ExportEntry(path: 'kept.md', content: 'yes'),
    ]);

    expect(File(outside).existsSync(), isFalse);
    // The safe entry in the same batch still lands.
    expect(File(p.join(root.path, 'inner', 'kept.md')).existsSync(), isTrue);
  });

  test('an empty batch leaves nothing behind but the directory', () async {
    final target = p.join(root.path, 'empty');
    await FileSystemNoteExportSink(target).write([]);

    expect(Directory(target).listSync(), isEmpty);
  });

  test('overwrites a file left by a previous export', () async {
    final sink = FileSystemNoteExportSink(root.path);
    await sink.write([const ExportEntry(path: 'A.md', content: 'old')]);
    await sink.write([const ExportEntry(path: 'A.md', content: 'new')]);

    expect(read('A.md'), 'new');
  });
}
