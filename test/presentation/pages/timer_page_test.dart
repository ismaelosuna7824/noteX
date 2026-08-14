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
import 'package:notex/domain/entities/project.dart';
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
import 'package:notex/presentation/widgets/app_picker_menu.dart';
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

  /// Read by [SyncEngine.syncIfAuthenticated] — [DeleteProjectUseCase]
  /// calls it as its last step. `false` lets that call return immediately
  /// instead of touching the (deliberately throwing) unused sync/
  /// connectivity fakes, the same "opt out of sync cleanly" shape a real
  /// signed-out session has.
  @override
  bool get isAuthenticated => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

/// A [SyncEngine] whose `syncIfAuthenticated()` resolves as a clean no-op
/// (never-authenticated) instead of throwing — needed wherever a test
/// actually exercises a delete flow through to completion, unlike
/// [_unusedSyncEngine], which is for collaborators the suite never touches
/// at all.
SyncEngine _noopSyncEngine() => SyncEngine(
      auth: _FakeAuthRepositoryWithStream(),
      syncService: _UnusedSyncService(),
      connectivity: _UnusedConnectivityService(),
    );

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
        _noopSyncEngine(),
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

  group(
      '"Delete Entry" confirmation button resolves its foreground from its '
      'own background, not a literal (sweep for the same defect as "New '
      'Task")', () {
    testWidgets(
        "the Delete button's foreground contrasts with its own literal red "
        'background instead of resolving against the seed-tinted '
        'onPrimary default', (tester) async {
      final now = DateTime.now();
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-1',
        description: 'To be deleted',
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now,
        updatedAt: now,
      ));

      await pumpTimerPage(tester);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Delete Entry'), findsOneWidget);

      final deleteButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(FilledButton),
        ),
      );
      final background =
          deleteButton.style?.backgroundColor?.resolve(<WidgetState>{});
      final expectedForeground =
          background!.computeLuminance() > 0.5 ? Colors.black : Colors.white;

      expect(
        deleteButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        expectedForeground,
        reason: 'left unset, the label resolves against '
            "colorScheme.onPrimary (the seed's tonal primary), not the "
            'literal background colour actually painted',
      );
    });
  });

  group('the timer\'s own project picker, converted onto the shared '
      'AppPickerMenu', () {
    Future<Project> saveProject(String id, String name, int colorValue) async {
      final now = DateTime.now();
      final project = Project(
        id: id,
        name: name,
        colorValue: colorValue,
        createdAt: now,
        updatedAt: now,
      );
      await projectRepository.save(project);
      return project;
    }

    // Target the picker by widget TYPE, not its chevron icon — the week
    // total's own project breakdown (_TimerBar's other Icons.expand_more_
    // rounded, shown whenever more than one project has tracked time this
    // week) would otherwise make icon-based lookup ambiguous.
    Future<void> openProjectMenu(WidgetTester tester) async {
      await tester.tap(find.byType(AppPickerMenu<String?>));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'lists "All projects", "No Project" and every project, each with '
        'its own correct check — both "All projects" and "No Project" '
        'start checked, matching the original picker\'s dual-state default',
        (tester) async {
      await saveProject('proj-alpha', 'Alpha', Colors.red.toARGB32());
      await saveProject('proj-beta', 'Beta', Colors.blue.toARGB32());

      await pumpTimerPage(tester);
      await openProjectMenu(tester);

      expect(find.text('All projects'), findsOneWidget);
      expect(
        find.text('No Project'),
        findsWidgets,
        reason: 'the chip trigger itself also reads "No Project" while '
            'unset — the row must exist regardless',
      );
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(
        find.byIcon(Icons.check_rounded),
        findsNWidgets(2),
        reason: 'with no filter and no draft project chosen yet, both '
            '"All projects" (filterProjectId == null) and "No Project" '
            '(draftProjectId == null) legitimately show a check at once — '
            'the same two independent states the original hand-rolled '
            'menu tracked',
      );
    });

    testWidgets(
        'selecting "All projects", "No Project" or a specific project '
        'filters the entries list exactly as before', (tester) async {
      final alpha =
          await saveProject('proj-alpha', 'Alpha', Colors.red.toARGB32());
      final now = DateTime.now();
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-alpha',
        description: 'Ship the feature',
        projectId: alpha.id,
        startTime: now.subtract(const Duration(hours: 2)),
        endTime: now.subtract(const Duration(hours: 1)),
        updatedAt: now,
      ));
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-none',
        description: 'Untracked work',
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now,
        updatedAt: now,
      ));

      await pumpTimerPage(tester);

      // Filter to Alpha. `.last` scopes the tap to the menu's own row —
      // the week's project breakdown legend (driven by this same tracked
      // entry) also renders a "Alpha" label, unrelated to this picker.
      await openProjectMenu(tester);
      await tester.tap(find.text('Alpha').last);
      await tester.pumpAndSettle();

      expect(find.text('Ship the feature'), findsOneWidget);
      expect(find.text('Untracked work'), findsNothing);

      // Filter to No Project.
      await openProjectMenu(tester);
      await tester.tap(find.text('No Project').last);
      await tester.pumpAndSettle();

      expect(find.text('Untracked work'), findsOneWidget);
      expect(find.text('Ship the feature'), findsNothing);

      // Back to All projects.
      await openProjectMenu(tester);
      await tester.tap(find.text('All projects').last);
      await tester.pumpAndSettle();

      expect(find.text('Ship the feature'), findsOneWidget);
      expect(find.text('Untracked work'), findsOneWidget);
    });

    testWidgets(
        'the inline delete icon opens the same destructive confirmation as '
        'before, and confirming it soft-deletes the project AND its time '
        'entries', (tester) async {
      final alpha =
          await saveProject('proj-alpha', 'Alpha', Colors.red.toARGB32());
      final now = DateTime.now();
      await timeEntryRepository.save(TimeEntry(
        id: 'entry-alpha',
        description: 'Ship the feature',
        projectId: alpha.id,
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now,
        updatedAt: now,
      ));

      await pumpTimerPage(tester);
      await openProjectMenu(tester);

      await tester.tap(find.byTooltip('Delete project'));
      await tester.pumpAndSettle();

      expect(find.text('Delete "Alpha"?'), findsOneWidget);
      expect(
        find.text(
          'This will permanently delete the project and all 1 time '
          'entry inside it.',
        ),
        findsOneWidget,
        reason: 'the confirmation wording, including the entry count, must '
            'survive the conversion unchanged',
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final deletedProject = await projectRepository.getById(alpha.id);
      expect(deletedProject!.deletedAt, isNotNull);
      final deletedEntry = await timeEntryRepository.getById('entry-alpha');
      expect(
        deletedEntry!.deletedAt,
        isNotNull,
        reason: 'deleting a project must soft-delete its time entries too '
            '— DeleteProjectUseCase\'s existing contract',
      );

      await openProjectMenu(tester);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets(
        'the footer "New Project" action still creates a project through '
        'the existing use case and selects it', (tester) async {
      await pumpTimerPage(tester);
      await openProjectMenu(tester);

      await tester.tap(find.text('New Project'));
      await tester.pumpAndSettle();

      expect(find.text('New Project'), findsWidgets);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Gamma',
      );
      // Deliberately asserted on STATE, not the widget tree, and without
      // any further `pump()`/`pumpAndSettle()` call after this tap.
      // `_showNewProjectDialog` disposes its own `nameController`
      // manually right after `await showAnimatedDialog(...)` resolves —
      // i.e. right after `Navigator.pop`, while the dialog's 250ms close
      // transition is STILL animating and the (now-disposed) `TextField`
      // is still mounted. A pre-existing, documented defect this task
      // explicitly excludes from the fix ("do not fix
      // _showNewProjectDialog controller disposal"): ANY subsequent frame
      // pump ticks that still-running exit transition and throws — proven
      // by first writing this test WITH a follow-up `pump()`, which
      // reliably reproduced it. `await tester.tap(...)` itself already
      // drains the microtasks `createProject`/`setDraftProject`/
      // `Navigator.pop` need, so the use-case path's effect is fully
      // observable on `timerState`/`projectRepository` without touching
      // that landmine.
      await tester.tap(find.text('Create'));

      expect(
        timerState.draftProjectId,
        isNotNull,
        reason: 'the newly-created project must be the current selection',
      );
      final newProject =
          await projectRepository.getById(timerState.draftProjectId!);
      expect(
        newProject?.name,
        'Gamma',
        reason: 'the footer action must create through the same '
            'TimerState.createProject use-case path every other project '
            'creation already goes through',
      );
    });

    testWidgets(
        'every menu row and the inline delete icon meet the 44x44 minimum '
        'tap target', (tester) async {
      await saveProject('proj-alpha', 'Alpha', Colors.red.toARGB32());

      await pumpTimerPage(tester);
      await openProjectMenu(tester);

      // Same precedent as app_picker_menu_test.dart's own 44x44 assertion:
      // every PopupMenuItem defaults to a >=48 minimum height
      // (kMinInteractiveDimension), verified via the last rendered row.
      final lastRowSize = tester.getSize(find.byType(InkWell).last);
      expect(lastRowSize.height, greaterThanOrEqualTo(44));

      // The inline delete icon is the risk this brief calls out by name —
      // asserted directly, not assumed from the row's own height.
      final deleteSize = tester.getSize(find.byTooltip('Delete project'));
      expect(deleteSize.width, greaterThanOrEqualTo(44));
      expect(deleteSize.height, greaterThanOrEqualTo(44));
    });
  });
}
