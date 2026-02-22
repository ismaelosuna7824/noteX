import '../../../domain/entities/markdown_project.dart';
import '../../../domain/repositories/markdown_project_repository.dart';

/// Use case: Create a new markdown project (folder grouping).
class CreateMarkdownProjectUseCase {
  final MarkdownProjectRepository _repository;

  const CreateMarkdownProjectUseCase(this._repository);

  Future<MarkdownProject> execute({
    required String id,
    required String name,
    required int colorValue,
  }) async {
    final project = MarkdownProject.create(
      id: id,
      name: name,
      colorValue: colorValue,
    );
    await _repository.save(project);
    return project;
  }
}
