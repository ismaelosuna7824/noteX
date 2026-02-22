import '../../../domain/entities/markdown_project.dart';
import '../../../domain/repositories/markdown_project_repository.dart';

/// Use case: Retrieve markdown projects.
class GetMarkdownProjectsUseCase {
  final MarkdownProjectRepository _repository;

  const GetMarkdownProjectsUseCase(this._repository);

  Future<List<MarkdownProject>> getAll() => _repository.getAll();
  Future<MarkdownProject?> getById(String id) => _repository.getById(id);
}
