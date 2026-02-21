import '../../../domain/entities/project.dart';
import '../../../domain/repositories/project_repository.dart';

class CreateProjectUseCase {
  final ProjectRepository _repository;
  const CreateProjectUseCase(this._repository);

  Future<Project> execute({
    required String id,
    required String name,
    required int colorValue,
  }) async {
    final project = Project(
      id: id,
      name: name,
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );
    await _repository.save(project);
    return project;
  }
}
