import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../content/note_content_format.dart';
import '../logging/app_logger.dart';
import 'database.dart';

/// One-time batch migration that rewrites every stored note's [content] from the
/// legacy Quill Delta JSON format to Markdown.
///
/// DATA-CRITICAL. This touches the user's real notes, so it is built to be safe
/// above all else:
///
/// * **Run-once** — a persisted flag (`content_markdown_migration_v1_done`) in
///   the drift `app_metadata` table makes the migration a no-op on every launch
///   after the first successful pass.
/// * **Automatic backup** — before any write, the WAL is checkpointed
///   (`PRAGMA wal_checkpoint(TRUNCATE)`) so the main `.sqlite` file is complete,
///   then the file is copied to `notex-premarkdown-backup-<epoch>.sqlite` in the
///   same folder. If the backup fails, the migration ABORTS without converting
///   anything and leaves the flag UNSET so it retries on the next launch.
/// * **Sync-safe** — each legacy note is converted with a *silent local content
///   update*: only the `content` column is written. `updatedAt`, `syncStatus`
///   and `version` are deliberately left untouched so the conversion does not
///   trigger a sync storm. Anything left as Delta remotely is still converted on
///   read by [NoteContentFormat].
/// * **Idempotent** — conversion is keyed on [NoteContentFormat.isLegacyDelta];
///   notes already in Markdown are skipped, so even a re-run (e.g. after a crash
///   before the flag was set) never double-converts or loses text.
class NoteMarkdownMigration {
  NoteMarkdownMigration(
    this._db, {
    Future<File?> Function()? dbFileResolver,
    AppLogger logger = const AppLogger('NoteMarkdownMigration'),
  })  : _dbFileResolver = dbFileResolver ?? _defaultDbFileResolver,
        _logger = logger;

  /// Run-once flag key stored in the `app_metadata` table.
  static const String migrationFlagKey = 'content_markdown_migration_v1_done';

  final AppDatabase _db;

  /// Resolves the on-disk `.sqlite` file to back up. Returns `null` when there
  /// is nothing to back up (fresh install, or an in-memory test database).
  final Future<File?> Function() _dbFileResolver;

  final AppLogger _logger;

  /// Runs the migration once. Safe to call on every startup — this method NEVER
  /// throws, so a migration failure can never gate app startup. On any
  /// unexpected error the app continues normally and notes stay in their stored
  /// format, converting lazily on read.
  Future<void> run() async {
    try {
      await _run();
    } catch (error, stackTrace) {
      _logger.error(
        'Delta→Markdown migration failed unexpectedly — app continues normally; '
        'notes convert lazily on read.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _run() async {
    // 1. RUN-ONCE GUARD — return immediately if already done.
    final done = await _db.getMetadata(migrationFlagKey);
    if (done == 'true') {
      return;
    }

    // 2. AUTOMATIC BACKUP (before any write). If it fails, ABORT without
    //    converting and leave the flag UNSET so we retry next launch.
    final String? backupPath;
    try {
      backupPath = await _createBackup();
    } catch (error, stackTrace) {
      _logger.error(
        'Backup failed — aborting migration WITHOUT converting. '
        'Will retry on next launch.',
        error,
        stackTrace,
      );
      return;
    }

    // 3. CONVERT — legacy Delta notes only, content column only. Wrapped in a
    //    transaction so a run is all-or-nothing; a failure leaves the flag unset
    //    and the (already backed-up) data untouched for a clean retry.
    var total = 0;
    var converted = 0;
    var skipped = 0;
    try {
      await _db.transaction(() async {
        final rows = await _db.select(_db.noteEntries).get();
        total = rows.length;
        for (final row in rows) {
          if (!NoteContentFormat.isLegacyDelta(row.content)) {
            skipped++;
            continue;
          }
          final markdown = NoteContentFormat.ensureMarkdown(row.content);
          // Silent local update: write ONLY content. Do NOT bump updatedAt,
          // syncStatus or version (sync-safety).
          await (_db.update(_db.noteEntries)
                ..where((t) => t.id.equals(row.id)))
              .write(NoteEntriesCompanion(content: Value(markdown)));
          converted++;
        }
      });
    } catch (error, stackTrace) {
      _logger.error(
        'Conversion failed — flag left UNSET for retry. A backup was already '
        'written at: ${backupPath ?? '(none — no db file)'}',
        error,
        stackTrace,
      );
      return;
    }

    // 4. LOG a summary.
    _logger.info(
      'Legacy Delta→Markdown migration complete. '
      'total=$total converted=$converted skipped=$skipped '
      'backup=${backupPath ?? '(skipped — no db file)'}',
    );

    // 5. Set the run-once flag ONLY after a fully successful pass.
    await _db.setMetadata(migrationFlagKey, 'true');
  }

  /// Checkpoints the WAL and copies the live database file to a timestamped
  /// backup in the same folder. Returns the backup path, or `null` when there is
  /// no database file to back up (fresh install / in-memory database).
  Future<String?> _createBackup() async {
    final file = await _dbFileResolver();
    if (file == null || !await file.exists()) {
      // Fresh install (no notes yet) or in-memory DB — nothing to back up.
      return null;
    }

    // Fold the WAL back into the main file so the copied .sqlite is complete.
    await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

    final epoch = DateTime.now().millisecondsSinceEpoch;
    final backupPath =
        p.join(file.parent.path, 'notex-premarkdown-backup-$epoch.sqlite');
    await file.copy(backupPath);
    return backupPath;
  }

  /// Default resolver for the production database file:
  /// `<app documents>/NoteX/notex.sqlite`.
  static Future<File?> _defaultDbFileResolver() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'NoteX', 'notex.sqlite'));
  }
}
