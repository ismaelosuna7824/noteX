import '../../../domain/entities/project.dart';
import '../../../domain/repositories/project_repository.dart';

class GetProjectsUseCase {
  final ProjectRepository _repository;
  const GetProjectsUseCase(this._repository);

  Future<List<Project>> getAll() => _repository.getAll();
  Future<Project?> getById(String id) => _repository.getById(id);
}
