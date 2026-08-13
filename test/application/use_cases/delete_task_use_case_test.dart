import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/services/sync_engine.dart';
import 'package:notex/application/use_cases/task/delete_task_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/repositories/auth_repository.dart';
import 'package:notex/domain/services/connectivity_service.dart';
import 'package:notex/domain/services/sync_service.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';

/// Minimal fake satisfying [AuthRepository] — every member unused by this
/// test throws, so an accidental new call site is caught immediately.
class _UnusedAuthRepository implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

class _UnusedConnectivityService implements ConnectivityService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

class _UnusedSyncService implements SyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

/// Spies on [SyncEngine.syncIfAuthenticated] without exercising the real
/// auth/connectivity/sync collaborators.
class _SpySyncEngine extends SyncEngine {
  bool syncIfAuthenticatedCalled = false;

  _SpySyncEngine()
      : super(
          auth: _UnusedAuthRepository(),
          syncService: _UnusedSyncService(),
          connectivity: _UnusedConnectivityService(),
        );

  @override
  Future<void> syncIfAuthenticated() async {
    syncIfAuthenticatedCalled = true;
  }
}

/// Characterization tests for [DeleteTaskUseCase], written BEFORE the
/// task-tracker rename touches any `lib/` code.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;
  late _SpySyncEngine syncEngine;
  late DeleteTaskUseCase useCase;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTaskRepository(db);
    syncEngine = _SpySyncEngine();
    useCase = DeleteTaskUseCase(repository, syncEngine);
  });

  tearDown(() async {
    await db.close();
  });

  test('soft-deletes an existing task (sets deletedAt, does not remove the row)',
      () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    await useCase.execute('r1');

    final row = await repository.getById('r1');
    expect(row, isNotNull, reason: 'soft-delete keeps the row, unlike delete()');
    expect(row!.deletedAt, isNotNull);
    expect(row.isDeleted, isTrue);
  });

  test('is a no-op on the repository when the task id does not exist',
      () async {
    await useCase.execute('missing');

    expect(await repository.getAll(), isEmpty);
  });

  test('always calls syncEngine.syncIfAuthenticated, even for a missing id',
      () async {
    await useCase.execute('missing');

    expect(syncEngine.syncIfAuthenticatedCalled, isTrue);
  });

  test('calls syncEngine.syncIfAuthenticated after a successful soft-delete',
      () async {
    await repository.save(Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));

    await useCase.execute('r1');

    expect(syncEngine.syncIfAuthenticatedCalled, isTrue);
  });
}
