import 'package:drift/drift.dart';

import '../../domain/entities/project.dart' as domain;
import '../../domain/repositories/project_repository.dart';
import 'database.dart';

/// Drift/SQLite adapter for [ProjectRepository].
class DriftProjectRepository implements ProjectRepository {
  final AppDatabase _db;

  DriftProjectRepository(this._db);

  @override
  Future<List<domain.Project>> getAll() async {
    final rows = await (_db.select(_db.projects)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map((r) => AppDatabase.projectToDomain(r)).toList();
  }

  @override
  Future<domain.Project?> getById(String id) async {
    final row = await (_db.select(_db.projects)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? AppDatabase.projectToDomain(row) : null;
  }

  @override
  Future<void> save(domain.Project project) async {
    await _db
        .into(_db.projects)
        .insertOnConflictUpdate(AppDatabase.projectToCompanion(project));
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.projects)..where((t) => t.id.equals(id))).go();
  }
}
