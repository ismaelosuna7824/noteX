import '../../../domain/entities/note_project.dart';
import '../../../domain/repositories/note_project_repository.dart';

/// Use case: Create a new note project (folder grouping for notes).
class CreateNoteProjectUseCase {
  final NoteProjectRepository _repository;

  const CreateNoteProjectUseCase(this._repository);

  Future<NoteProject> execute({
    required String id,
    required String name,
    required int colorValue,
  }) async {
    final project = NoteProject.create(
      id: id,
      name: name,
      colorValue: colorValue,
    );
    await _repository.save(project);
    return project;
  }
}
