import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/note/permanent_delete_note_use_case.dart';
import 'package:notex/application/use_cases/task/resolve_task_note_link_use_case.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/domain/value_objects/note_link_resolution.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_note_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftNoteRepository repository;
  late ResolveTaskNoteLinkUseCase useCase;

  Note note({String id = 'n1', DateTime? deletedAt}) => Note(
        id: id,
        title: 'Meeting notes',
        content: 'agenda',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        deletedAt: deletedAt,
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftNoteRepository(db);
    useCase = ResolveTaskNoteLinkUseCase(repository);
  });

  tearDown(() async {
    await db.close();
  });

  test('a live note resolves to found', () async {
    await repository.save(note());

    final result = await useCase.execute('n1');

    expect(result.status, NoteLinkStatus.found);
    expect(result.note?.id, 'n1');
  });

  test('a soft-deleted note resolves to inTrash, not found', () async {
    await repository.save(note(deletedAt: DateTime(2026, 1, 2)));

    final result = await useCase.execute('n1');

    expect(result.status, NoteLinkStatus.inTrash);
    expect(result.note?.id, 'n1', reason: 'the link is preserved, not lost');
  });

  test('an id that never existed resolves to missing', () async {
    final result = await useCase.execute('does-not-exist');

    expect(result.status, NoteLinkStatus.missing);
    expect(result.note, isNull);
  });

  test(
    'a permanently deleted note resolves to missing, distinct from '
    'in-trash',
    () async {
      await repository.save(note(deletedAt: DateTime(2026, 1, 2)));
      // Sanity: it is in-trash before the hard delete.
      expect((await useCase.execute('n1')).status, NoteLinkStatus.inTrash);

      await PermanentDeleteNoteUseCase(repository).execute('n1');

      final result = await useCase.execute('n1');
      expect(result.status, NoteLinkStatus.missing);
    },
  );

  test(
    'resolves via getById, never a deletedAt-filtered list — a soft-deleted '
    'note is invisible to getAll() but still resolves to inTrash',
    () async {
      await repository.save(note(deletedAt: DateTime(2026, 1, 2)));

      expect(await repository.getAll(), isEmpty);
      final result = await useCase.execute('n1');
      expect(result.status, NoteLinkStatus.inTrash);
    },
  );
}
