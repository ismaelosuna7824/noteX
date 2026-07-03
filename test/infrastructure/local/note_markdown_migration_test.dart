import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/infrastructure/content/note_content_format.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/note_markdown_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  // Sample note contents.
  const deltaContent =
      '[{"insert":"Hello "},{"insert":"world","attributes":{"bold":true}},{"insert":"\\n"}]';
  const markdownContent = '# Title\n\nSome **markdown** text';
  const emptyDeltaContent = '[]';
  const plainTextContent = 'just plain text with no formatting';

  final fixedCreatedAt = DateTime.utc(2024, 1, 1, 8);
  final fixedUpdatedAt = DateTime.utc(2024, 1, 2, 9);

  Future<void> seedNote({
    required String id,
    required String content,
    String syncStatus = 'synced',
    int version = 7,
  }) async {
    await db.into(db.noteEntries).insert(
          NoteEntriesCompanion.insert(
            id: id,
            content: Value(content),
            createdAt: fixedCreatedAt,
            updatedAt: fixedUpdatedAt,
            syncStatus: Value(syncStatus),
            version: Value(version),
          ),
        );
  }

  Future<NoteEntry> fetch(String id) async {
    return (db.select(db.noteEntries)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedNote(id: 'delta', content: deltaContent);
    await seedNote(id: 'markdown', content: markdownContent);
    await seedNote(id: 'empty', content: emptyDeltaContent);
    await seedNote(id: 'plain', content: plainTextContent);
  });

  tearDown(() async {
    await db.close();
  });

  test('converts the legacy Delta note to its Markdown equivalent', () async {
    // Backup is skipped for the in-memory DB (resolver returns null).
    await NoteMarkdownMigration(db, dbFileResolver: () async => null).run();

    final delta = await fetch('delta');
    expect(delta.content, NoteContentFormat.ensureMarkdown(deltaContent));
    // Sanity: the conversion actually changed something.
    expect(delta.content, isNot(deltaContent));
    expect(delta.content, 'Hello **world**');
  });

  test('leaves an already-Markdown note unchanged', () async {
    await NoteMarkdownMigration(db, dbFileResolver: () async => null).run();

    final markdown = await fetch('markdown');
    expect(markdown.content, markdownContent);

    final plain = await fetch('plain');
    expect(plain.content, plainTextContent);
  });

  test('converts the empty Delta document to an empty string', () async {
    await NoteMarkdownMigration(db, dbFileResolver: () async => null).run();

    final empty = await fetch('empty');
    expect(empty.content, '');
  });

  test('does NOT change metadata for any note (sync-safety)', () async {
    // Snapshot the stored rows before migrating (drift round-trips DateTime
    // through the local timezone, so compare drift-read values to drift-read
    // values rather than to the original UTC constants).
    final ids = ['delta', 'markdown', 'empty', 'plain'];
    final before = {for (final id in ids) id: await fetch(id)};

    await NoteMarkdownMigration(db, dbFileResolver: () async => null).run();

    for (final id in ids) {
      final row = await fetch(id);
      final prior = before[id]!;
      expect(row.updatedAt, prior.updatedAt, reason: '$id updatedAt bumped');
      expect(row.createdAt, prior.createdAt, reason: '$id createdAt changed');
      expect(row.syncStatus, prior.syncStatus, reason: '$id syncStatus changed');
      expect(row.version, prior.version, reason: '$id version bumped');
    }
  });

  test('running the migration a second time is a no-op (run-once flag)',
      () async {
    await NoteMarkdownMigration(db, dbFileResolver: () async => null).run();

    // Capture the full state after the first pass.
    final afterFirst = {
      for (final id in ['delta', 'markdown', 'empty', 'plain'])
        id: await fetch(id),
    };

    // Sabotage: if the migration ran again it would re-read and could re-touch
    // rows. Manually flip a converted note back to Delta to prove the guard
    // prevents any second conversion.
    await (db.update(db.noteEntries)..where((t) => t.id.equals('delta')))
        .write(const NoteEntriesCompanion(content: Value(deltaContent)));

    await NoteMarkdownMigration(db, dbFileResolver: () async => null).run();

    // The guard short-circuits, so the manually-restored Delta is left as-is.
    final delta = await fetch('delta');
    expect(delta.content, deltaContent,
        reason: 'second run must be a no-op and not re-convert');

    // Untouched notes are still exactly as the first pass left them.
    for (final id in ['markdown', 'empty', 'plain']) {
      final row = await fetch(id);
      expect(row.content, afterFirst[id]!.content);
      expect(row.updatedAt, afterFirst[id]!.updatedAt);
      expect(row.syncStatus, afterFirst[id]!.syncStatus);
      expect(row.version, afterFirst[id]!.version);
    }
  });

  test('sets the run-once flag only after a successful pass', () async {
    expect(await db.getMetadata(NoteMarkdownMigration.migrationFlagKey), isNull);

    await NoteMarkdownMigration(db, dbFileResolver: () async => null).run();

    expect(
      await db.getMetadata(NoteMarkdownMigration.migrationFlagKey),
      'true',
    );
  });

  test('creates a backup copy of the db file before converting', () async {
    final tempDir = await Directory.systemTemp.createTemp('notex_backup_test');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final dbFile = File('${tempDir.path}/notex.sqlite');
    await dbFile.writeAsString('fake-sqlite-bytes');

    await NoteMarkdownMigration(db, dbFileResolver: () async => dbFile).run();

    final backups = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('notex-premarkdown-backup-'))
        .toList();
    expect(backups, hasLength(1),
        reason: 'exactly one timestamped backup should be created');
    expect(await backups.single.readAsString(), 'fake-sqlite-bytes');

    // Conversion still ran.
    final delta = await fetch('delta');
    expect(delta.content, 'Hello **world**');
  });

  test('aborts without converting when backup fails', () async {
    await NoteMarkdownMigration(
      db,
      dbFileResolver: () async => throw const FileSystemException('disk full'),
    ).run();

    // Nothing converted — original Delta preserved.
    final delta = await fetch('delta');
    expect(delta.content, deltaContent);

    // Flag left UNSET so it can retry on the next launch.
    expect(
      await db.getMetadata(NoteMarkdownMigration.migrationFlagKey),
      isNull,
    );
  });
}
