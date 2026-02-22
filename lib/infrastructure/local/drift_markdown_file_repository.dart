import 'package:drift/drift.dart';

import '../../domain/entities/markdown_file.dart' as domain;
import '../../domain/repositories/markdown_file_repository.dart';
import '../../domain/value_objects/sync_status.dart';
import 'database.dart';

/// Infrastructure adapter: Implements MarkdownFileRepository using Drift (SQLite).
class DriftMarkdownFileRepository implements MarkdownFileRepository {
  final AppDatabase _db;

  DriftMarkdownFileRepository(this._db);

  @override
  Future<List<domain.MarkdownFile>> getAll() async {
    final rows = await (_db.select(_db.markdownFileEntries)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map((r) => AppDatabase.markdownFileToDomain(r)).toList();
  }

  @override
  Future<domain.MarkdownFile?> getById(String id) async {
    final row = await (_db.select(_db.markdownFileEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? AppDatabase.markdownFileToDomain(row) : null;
  }

  @override
  Future<List<domain.MarkdownFile>> getByProjectId(String? projectId) async {
    final rows = await (_db.select(_db.markdownFileEntries)
          ..where((t) {
            final notDeleted = t.deletedAt.isNull();
            if (projectId == null) {
              return notDeleted & t.projectId.isNull();
            }
            return notDeleted & t.projectId.equals(projectId);
          })
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map((r) => AppDatabase.markdownFileToDomain(r)).toList();
  }

  @override
  Future<List<domain.MarkdownFile>> getBySyncStatus(SyncStatus status) async {
    final rows = await (_db.select(_db.markdownFileEntries)
          ..where((t) => t.syncStatus.equals(status.name)))
        .get();
    return rows.map((r) => AppDatabase.markdownFileToDomain(r)).toList();
  }

  @override
  Future<void> save(domain.MarkdownFile file) async {
    await _db.into(_db.markdownFileEntries).insertOnConflictUpdate(
          AppDatabase.markdownFileToCompanion(file),
        );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.markdownFileEntries)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<void> deleteByProjectId(String projectId) async {
    await (_db.delete(_db.markdownFileEntries)
          ..where((t) => t.projectId.equals(projectId)))
        .go();
  }

  @override
  Future<List<domain.MarkdownFile>> search(String query) async {
    final pattern = '%$query%';
    final rows = await (_db.select(_db.markdownFileEntries)
          ..where((t) =>
              t.deletedAt.isNull() &
              (t.title.like(pattern) | t.content.like(pattern)))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map((r) => AppDatabase.markdownFileToDomain(r)).toList();
  }

  @override
  Future<int> count() async {
    final countExpr = _db.markdownFileEntries.id.count();
    final query = _db.selectOnly(_db.markdownFileEntries)
      ..addColumns([countExpr])
      ..where(_db.markdownFileEntries.deletedAt.isNull());
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  @override
  Future<List<domain.MarkdownFile>> getModifiedSince(DateTime since) async {
    final rows = await (_db.select(_db.markdownFileEntries)
          ..where((t) => t.updatedAt.isBiggerThanValue(since)))
        .get();
    return rows.map((r) => AppDatabase.markdownFileToDomain(r)).toList();
  }
}
