import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/time_entry.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_time_entry_repository.dart';

/// Coverage for [DriftTimeEntryRepository.getByTaskId] — powers the task
/// detail dialog's "total tracked time" figure (settled decision: surface
/// the total instead of faking a pause/resume single entry).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTimeEntryRepository repository;

  TimeEntry buildEntry({
    required String id,
    String? taskId,
    bool running = false,
    DateTime? deletedAt,
  }) {
    final start = DateTime(2026, 1, 1, 9);
    return TimeEntry(
      id: id,
      description: 'work',
      startTime: start,
      endTime: running ? null : start.add(const Duration(hours: 1)),
      updatedAt: start,
      taskId: taskId,
      deletedAt: deletedAt,
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTimeEntryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('getByTaskId', () {
    test('returns only entries linked to the given task', () async {
      await repository.save(buildEntry(id: 'e1', taskId: 'task-1'));
      await repository.save(buildEntry(id: 'e2', taskId: 'task-2'));
      await repository.save(buildEntry(id: 'e3', taskId: 'task-1'));

      final result = await repository.getByTaskId('task-1');

      expect(result.map((e) => e.id), containsAll(['e1', 'e3']));
      expect(result.map((e) => e.id), isNot(contains('e2')));
    });

    test('excludes soft-deleted entries', () async {
      await repository.save(buildEntry(
        id: 'e1',
        taskId: 'task-1',
        deletedAt: DateTime(2026, 1, 2),
      ));

      final result = await repository.getByTaskId('task-1');

      expect(result, isEmpty);
    });

    test('returns an empty list when no entry links to the task', () async {
      await repository.save(buildEntry(id: 'e1', taskId: 'task-2'));

      final result = await repository.getByTaskId('task-1');

      expect(result, isEmpty);
    });

    test('includes a currently-running entry (null endTime)', () async {
      await repository.save(buildEntry(id: 'e1', taskId: 'task-1', running: true));

      final result = await repository.getByTaskId('task-1');

      expect(result, hasLength(1));
      expect(result.single.isRunning, isTrue);
    });
  });
}
