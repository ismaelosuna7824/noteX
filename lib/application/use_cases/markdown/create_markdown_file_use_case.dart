import '../../../domain/entities/markdown_file.dart';
import '../../../domain/repositories/markdown_file_repository.dart';

/// Use case: Create a new markdown file.
class CreateMarkdownFileUseCase {
  final MarkdownFileRepository _repository;

  const CreateMarkdownFileUseCase(this._repository);

  Future<MarkdownFile> execute({
    required String id,
    required String title,
    String content = '',
    String? projectId,
  }) async {
    final file = MarkdownFile.create(
      id: id,
      title: title,
      content: content,
      projectId: projectId,
    );
    await _repository.save(file);
    return file;
  }
}
