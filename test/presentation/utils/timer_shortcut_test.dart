import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/timer/create_project_use_case.dart';
import 'package:notex/application/use_cases/timer/delete_project_use_case.dart';
import 'package:notex/application/use_cases/timer/delete_time_entry_use_case.dart';
import 'package:notex/application/use_cases/timer/get_projects_use_case.dart';
import 'package:notex/application/use_cases/timer/get_time_entries_use_case.dart';
import 'package:notex/application/use_cases/timer/log_time_entry_use_case.dart';
import 'package:notex/application/use_cases/timer/start_timer_use_case.dart';
import 'package:notex/application/use_cases/timer/stop_timer_use_case.dart';
import 'package:notex/application/use_cases/timer/update_time_entry_use_case.dart';
import 'package:notex/application/use_cases/task/transition_task_status_use_case.dart';
import 'package:notex/application/services/sync_engine.dart';
import 'package:notex/domain/repositories/auth_repository.dart';
import 'package:notex/domain/services/connectivity_service.dart';
import 'package:notex/domain/services/sync_service.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_project_repository.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';
import 'package:notex/infrastructure/local/drift_time_entry_repository.dart';
import 'package:notex/presentation/state/timer_state.dart';
import 'package:notex/presentation/utils/timer_shortcut.dart';

/// Minimal throwing fakes — same `_UnusedX` pattern as `timer_page_test.dart`.
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

SyncEngine _unusedSyncEngine() => SyncEngine(
      auth: _UnusedAuthRepository(),
      syncService: _UnusedSyncService(),
      connectivity: _UnusedConnectivityService(),
    );

/// Covers the Cmd/Ctrl+Shift+T shortcut's toggle semantics: start when idle,
/// stop when running — exercised against a real [TimerState] (in-memory
/// Drift DB, same fixture shape as `timer_page_test.dart`) so the assertion
/// is against actual `isRunning`/entry state, not a mocked call count.
void main() {
  late AppDatabase db;
  late TimerState timerState;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final projectRepository = DriftProjectRepository(db);
    final timeEntryRepository = DriftTimeEntryRepository(db);
    final taskRepository = DriftTaskRepository(db);

    timerState = TimerState(
      createProject: CreateProjectUseCase(projectRepository),
      getProjects: GetProjectsUseCase(projectRepository),
      deleteProject: DeleteProjectUseCase(
        projectRepository,
        timeEntryRepository,
        _unusedSyncEngine(),
      ),
      startTimer: StartTimerUseCase(
        timeEntryRepository,
        TransitionTaskStatusUseCase(taskRepository),
      ),
      stopTimer: StopTimerUseCase(timeEntryRepository),
      getEntries: GetTimeEntriesUseCase(timeEntryRepository),
      deleteEntry: DeleteTimeEntryUseCase(timeEntryRepository),
      updateEntry: UpdateTimeEntryUseCase(timeEntryRepository),
      logEntry: LogTimeEntryUseCase(timeEntryRepository),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('starts the timer when none is running', () async {
    expect(timerState.isRunning, isFalse);

    await toggleRunningTimer(timerState);

    expect(timerState.isRunning, isTrue);
  });

  test('stops the running timer instead of starting a second one', () async {
    await timerState.startTimer();
    expect(timerState.isRunning, isTrue);

    await toggleRunningTimer(timerState);

    expect(timerState.isRunning, isFalse);
  });
}
