import '../../../domain/entities/markdown_file.dart';
import '../../../domain/repositories/markdown_file_repository.dart';

/// Use case: Retrieve markdown files.
class GetMarkdownFilesUseCase {
  final MarkdownFileRepository _repository;

  const GetMarkdownFilesUseCase(this._repository);

  Future<List<MarkdownFile>> getAll() => _repository.getAll();
  Future<MarkdownFile?> getById(String id) => _repository.getById(id);
  Future<List<MarkdownFile>> getByProjectId(String? projectId) =>
      _repository.getByProjectId(projectId);
  Future<List<MarkdownFile>> search(String query) => _repository.search(query);
  Future<int> count() => _repository.count();
}
