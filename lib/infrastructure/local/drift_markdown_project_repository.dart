import 'package:drift/drift.dart';

import '../../domain/entities/markdown_project.dart' as domain;
import '../../domain/repositories/markdown_project_repository.dart';
import '../../domain/value_objects/sync_status.dart';
import 'database.dart';

/// Drift/SQLite adapter for [MarkdownProjectRepository].
class DriftMarkdownProjectRepository implements MarkdownProjectRepository {
  final AppDatabase _db;

  DriftMarkdownProjectRepository(this._db);

  @override
  Future<List<domain.MarkdownProject>> getAll() async {
    final rows = await (_db.select(_db.markdownProjectEntries)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map((r) => AppDatabase.markdownProjectToDomain(r)).toList();
  }

  @override
  Future<domain.MarkdownProject?> getById(String id) async {
    final row = await (_db.select(_db.markdownProjectEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? AppDatabase.markdownProjectToDomain(row) : null;
  }

  @override
  Future<List<domain.MarkdownProject>> getBySyncStatus(
      SyncStatus status) async {
    final rows = await (_db.select(_db.markdownProjectEntries)
          ..where((t) => t.syncStatus.equals(status.name)))
        .get();
    return rows.map((r) => AppDatabase.markdownProjectToDomain(r)).toList();
  }

  @override
  Future<void> save(domain.MarkdownProject project) async {
    await _db.into(_db.markdownProjectEntries).insertOnConflictUpdate(
          AppDatabase.markdownProjectToCompanion(project),
        );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.markdownProjectEntries)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<List<domain.MarkdownProject>> getModifiedSince(
      DateTime since) async {
    final rows = await (_db.select(_db.markdownProjectEntries)
          ..where((t) => t.updatedAt.isBiggerThanValue(since)))
        .get();
    return rows.map((r) => AppDatabase.markdownProjectToDomain(r)).toList();
  }
}
