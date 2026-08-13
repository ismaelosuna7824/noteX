import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notex/application/services/auto_save_service.dart';
import 'package:notex/application/services/sync_engine.dart';
import 'package:notex/application/use_cases/check_for_update_use_case.dart';
import 'package:notex/application/use_cases/cleanup_empty_notes_use_case.dart';
import 'package:notex/application/use_cases/cleanup_expired_ephemeral_notes_use_case.dart';
import 'package:notex/application/use_cases/create_note_use_case.dart';
import 'package:notex/application/use_cases/delete_note_use_case.dart';
import 'package:notex/application/use_cases/get_notes_use_case.dart';
import 'package:notex/application/use_cases/note/create_note_project_use_case.dart';
import 'package:notex/application/use_cases/note/delete_note_project_use_case.dart';
import 'package:notex/application/use_cases/note/get_deleted_notes_use_case.dart';
import 'package:notex/application/use_cases/note/get_note_projects_use_case.dart';
import 'package:notex/application/use_cases/note/permanent_delete_note_use_case.dart';
import 'package:notex/application/use_cases/note/rename_note_project_use_case.dart';
import 'package:notex/application/use_cases/note/restore_note_use_case.dart';
import 'package:notex/application/use_cases/task/create_task_use_case.dart';
import 'package:notex/application/use_cases/task/delete_task_use_case.dart';
import 'package:notex/application/use_cases/task/get_tasks_use_case.dart';
import 'package:notex/application/use_cases/task/link_note_to_task_use_case.dart';
import 'package:notex/application/use_cases/task/transition_task_status_use_case.dart';
import 'package:notex/application/use_cases/task/unlink_note_from_task_use_case.dart';
import 'package:notex/application/use_cases/task/update_task_use_case.dart';
import 'package:notex/application/use_cases/timer/create_project_use_case.dart';
import 'package:notex/application/use_cases/timer/delete_project_use_case.dart';
import 'package:notex/application/use_cases/timer/delete_time_entry_use_case.dart';
import 'package:notex/application/use_cases/timer/get_projects_use_case.dart';
import 'package:notex/application/use_cases/timer/get_time_entries_use_case.dart';
import 'package:notex/application/use_cases/timer/log_time_entry_use_case.dart';
import 'package:notex/application/use_cases/timer/resolve_time_entry_task_use_case.dart';
import 'package:notex/application/use_cases/timer/start_timer_use_case.dart';
import 'package:notex/application/use_cases/timer/stop_timer_use_case.dart';
import 'package:notex/application/use_cases/timer/update_time_entry_use_case.dart';
import 'package:notex/application/use_cases/update_note_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/entities/time_entry.dart';
import 'package:notex/domain/repositories/auth_repository.dart';
import 'package:notex/domain/services/connectivity_service.dart';
import 'package:notex/domain/services/sync_service.dart';
import 'package:notex/domain/services/update_service.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_note_project_repository.dart';
import 'package:notex/infrastructure/local/drift_note_repository.dart';
import 'package:notex/infrastructure/local/drift_project_repository.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';
import 'package:notex/infrastructure/local/drift_time_entry_repository.dart';
import 'package:notex/presentation/pages/timer_page.dart';
import 'package:notex/presentation/state/app_state.dart';
import 'package:notex/presentation/state/task_state.dart';
import 'package:notex/presentation/state/theme_state.dart';
import 'package:notex/presentation/state/timer_state.dart';

/// Minimal throwing fakes for collaborators this suite never exercises —
/// same `_UnusedX` pattern already established in
/// `task_board_test.dart`/`delete_task_use_case_test.dart`: any accidental
/// new call site is caught immediately instead of silently no-op'ing.
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

class _UnusedUpdateService implements UpdateService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

SyncEngine _unusedSyncEngine() => SyncEngine(
      auth: _UnusedAuthRepository(),
      syncService: _UnusedSyncService(),
      connectivity: _UnusedConnectivityService(),
    );

/// [TimerPage] never reads its own `appState` constructor param (verified:
/// nothing in timer_page.dart references `widget.appState`) — it is only
/// required because the widget's own signature carries it. This fake auth
/// is needed regardless, since [AppState]'s constructor subscribes to
/// `authStateChanges` immediately.
class _FakeAuthRepositoryWithStream implements AuthRepository {
  @override
  Stream<bool> get authStateChanges => const Stream<bool>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

/// Covers item 4 of the task-detail-dialog/timer brief: a time entry that
/// carries a `taskId` gets a visible "came from a task" indicator, and
/// activating it opens that task's detail dialog through the shared public
/// entry point ([showTaskDetailDialog] in `task_board.dart`) — never a
/// duplicated dialog. Degrades gracefully (no crash, no empty dialog, no
/// entry mutation) when the task is missing or soft-deleted, mirroring the
/// linked-note precedent.
void main() {
  late AppDatabase db;
  late DriftTaskRepository taskRepository;
  late DriftTimeEntryRepository timeEntryRepository;
  late DriftProjectRepository projectRepository;
  late TaskState taskState;
  late TimerState timerState;
  late ThemeState themeState;
  late AppState appState;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    taskRepository = DriftTaskRepository(db);
    timeEntryRepository = DriftTimeEntryRepository(db);
    projectRepository = DriftProjectRepository(db);
    themeState = ThemeState();

    taskState = TaskState(
      createReminder: CreateTaskUseCase(taskRepository),
      getReminders: GetTasksUseCase(taskRepository),
      completeReminder: TransitionTaskStatusUseCase(taskRepository),
      updateReminder: UpdateTaskUseCase(taskRepository),
      deleteReminder: DeleteTaskUseCase(taskRepository, _unusedSyncEngine()),
      linkNote: LinkNoteToTaskUseCase(taskRepository),
      unlinkNote: UnlinkNoteFromTaskUseCase(taskRepository),
    );
    GetIt.instance.registerSingleton<TaskState>(taskState);

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
    GetIt.instance.registerSingleton<TimerState>(timerState);

    // Resolves the task behind a time entry's taskId — the affordance
    // under test. A REAL instance over the same in-memory database, same
    // convention as every other GetIt.instance<UseCase>() call site the
    // task detail dialog itself already relies on.
    GetIt.instance.registerSingleton<ResolveTimeEntryTaskUseCase>(
      ResolveTimeEntryTaskUseCase(taskRepository),
    );

    // The task detail dialog's own "total tracked time" figure
    // (_TaskDetailDialog._loadTimeEntries) resolves this via GetIt too.
    GetIt.instance.registerSingleton<GetTimeEntriesUseCase>(
      GetTimeEntriesUseCase(timeEntryRepository),
    );

    // TimerPage's constructor requires an AppState instance even though
    // it never reads it (see _FakeAuthRepositoryWithStream's doc) — built
    // with throwing fakes for every collaborator except the note
    // repositories (real, since they cost nothing extra over the shared
    // in-memory db) and the auth stream (needed at construction time).
    final noteRepository = DriftNoteRepository(db);
    final noteProjectRepository = DriftNoteProjectRepository(db);
    final updateNoteUseCase = UpdateNoteUseCase(noteRepository);
    appState = AppState(
      createNote: CreateNoteUseCase(noteRepository),
      getNotes: GetNotesUseCase(noteRepository),
      deleteNote: DeleteNoteUseCase(noteRepository),
      updateNote: updateNoteUseCase,
      createNoteProject: CreateNoteProjectUseCase(noteProjectRepository),
      getNoteProjects: GetNoteProjectsUseCase(noteProjectRepository),
      deleteNoteProject: DeleteNoteProjectUseCase(
        noteProjectRepository,
        noteRepository,
        _unusedSyncEngine(),
      ),
      renameNoteProject: RenameNoteProjectUseCase(noteProjectRepository),
      getDeletedNotes: GetDeletedNotesUseCase(noteRepository),
      restoreNote: RestoreNoteUseCase(noteRepository),
      permanentDeleteNote: PermanentDeleteNoteUseCase(noteRepository),
      checkForUpdate: CheckForUpdateUseCase(_UnusedUpdateService()),
      cleanupEmptyNotes: CleanupEmptyNotesUseCase(noteRepository),
      cleanupExpiredEphemeral:
          CleanupExpiredEphemeralNotesUseCase(noteRepository),
      updateService: _UnusedUpdateService(),
      autoSaveService: AutoSaveService(updateNoteUseCase),
      authRepository: _FakeAuthRepositoryWithStream(),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
    appState.dispose();
    timerState.dispose();
    await db.close();
  });

  Future<void> pumpTimerPage(WidgetTester tester) async {
    // Same generous desktop-sized surface task_board_test.dart uses for
    // the task detail dialog this page can open — the dialog is taller
    // and wider than flutter_test's default 800x600 phone-sized viewport.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: TimerPage(appState: appState, themeState: themeState),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a time entry started from a task can open that task\'s detail — '
      'item 4', () {
    testWidgets(
        'a single entry carrying a taskId shows a distinct "open task" '
        'indicator, and activating it opens the task detail dialog',
        (tester) async {
      final task = Task.create(id: 'task-1', title: 'Ship the feature');
      await taskRepository.save(task);

      final now = DateTime.now();
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-1',
        description: 'Ship the feature',
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now,
        updatedAt: now,
        taskId: 'task-1',
      ));

      await pumpTimerPage(tester);

      expect(
        find.byIcon(Icons.task_alt_outlined),
        findsOneWidget,
        reason: 'a task-linked entry must carry a visible indicator, not '
            'just the description text',
      );

      await tester.tap(find.byTooltip('Open task'));
      await tester.pumpAndSettle();

      expect(find.text('Task Details'), findsOneWidget);
      final titleField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Title'),
      );
      expect(titleField.controller!.text, 'Ship the feature',
          reason: 'the dialog opened must be for the resolved task, '
              'through the shared public entry point');
    });

    testWidgets('a free-text entry (no taskId) shows no task indicator',
        (tester) async {
      final now = DateTime.now();
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-1',
        description: 'Just typing',
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now,
        updatedAt: now,
      ));

      await pumpTimerPage(tester);

      expect(find.byIcon(Icons.task_alt_outlined), findsNothing);
    });

    testWidgets(
        'an entry whose task no longer exists degrades plainly instead of '
        'crashing or opening an empty dialog, and never mutates the entry',
        (tester) async {
      final now = DateTime.now();
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-1',
        description: 'Orphaned work',
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now,
        updatedAt: now,
        taskId: 'ghost-task',
      ));

      await pumpTimerPage(tester);

      await tester.tap(find.byTooltip('Open task'));
      await tester.pumpAndSettle();

      expect(find.text('This task no longer exists.'), findsOneWidget);
      expect(
        find.text('Task Details'),
        findsNothing,
        reason: 'must never open an empty/broken dialog for a missing task',
      );
      expect(tester.takeException(), isNull);

      final stillThere = await timeEntryRepository.getById('entry-1');
      expect(
        stillThere,
        isNotNull,
        reason: 'resolving a missing task must never cascade or mutate '
            'the time entry',
      );
      expect(stillThere!.taskId, 'ghost-task');
    });

    testWidgets(
        'the same degrade applies to an entry whose task exists but was '
        'soft-deleted', (tester) async {
      final task =
          Task.create(id: 'task-1', title: 'Deleted task').markDeleted();
      await taskRepository.save(task);

      final now = DateTime.now();
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-1',
        description: 'Deleted task',
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now,
        updatedAt: now,
        taskId: 'task-1',
      ));

      await pumpTimerPage(tester);

      await tester.tap(find.byTooltip('Open task'));
      await tester.pumpAndSettle();

      expect(find.text('This task no longer exists.'), findsOneWidget);
      expect(find.text('Task Details'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a grouped row (several runs of the same task-linked work) also '
        'carries the affordance, collapsed into one icon', (tester) async {
      final task = Task.create(id: 'task-1', title: 'Recurring work');
      await taskRepository.save(task);

      final now = DateTime.now();
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-1',
        description: 'Recurring work',
        startTime: now.subtract(const Duration(hours: 3)),
        endTime: now.subtract(const Duration(hours: 2, minutes: 30)),
        updatedAt: now,
        taskId: 'task-1',
      ));
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-2',
        description: 'Recurring work',
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now,
        updatedAt: now,
        taskId: 'task-1',
      ));

      await pumpTimerPage(tester);

      // Collapsed into one row — the description renders once, not twice.
      expect(find.text('Recurring work'), findsOneWidget);
      expect(
        find.byIcon(Icons.task_alt_outlined),
        findsOneWidget,
        reason: 'the collapsed group row must carry the affordance once, '
            'not require expanding it first',
      );

      await tester.tap(find.byTooltip('Open task'));
      await tester.pumpAndSettle();

      expect(find.text('Task Details'), findsOneWidget);
    });
  });
}
