import '../../../domain/entities/note_project.dart';
import '../../../domain/repositories/note_project_repository.dart';

/// Use case: Retrieve note projects.
class GetNoteProjectsUseCase {
  final NoteProjectRepository _repository;

  const GetNoteProjectsUseCase(this._repository);

  Future<List<NoteProject>> getAll() => _repository.getAll();
  Future<NoteProject?> getById(String id) => _repository.getById(id);
}
