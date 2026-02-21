import '../entities/project.dart';

/// Port: read/write access to projects.
abstract class ProjectRepository {
  Future<List<Project>> getAll();
  Future<Project?> getById(String id);
  Future<void> save(Project project); // insert or update
  Future<void> delete(String id);
}
