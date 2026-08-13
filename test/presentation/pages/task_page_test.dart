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
import 'package:notex/application/use_cases/task/resolve_task_note_link_use_case.dart';
import 'package:notex/application/use_cases/task/transition_task_status_use_case.dart';
import 'package:notex/application/use_cases/task/unlink_note_from_task_use_case.dart';
import 'package:notex/application/use_cases/task/update_task_use_case.dart';
import 'package:notex/application/use_cases/timer/create_project_use_case.dart';
import 'package:notex/application/use_cases/timer/delete_project_use_case.dart';
import 'package:notex/application/use_cases/timer/delete_time_entry_use_case.dart';
import 'package:notex/application/use_cases/timer/get_projects_use_case.dart';
import 'package:notex/application/use_cases/timer/get_time_entries_use_case.dart';
import 'package:notex/application/use_cases/timer/log_time_entry_use_case.dart';
import 'package:notex/application/use_cases/timer/start_timer_use_case.dart';
import 'package:notex/application/use_cases/timer/stop_timer_use_case.dart';
import 'package:notex/application/use_cases/timer/update_time_entry_use_case.dart';
import 'package:notex/application/use_cases/update_note_use_case.dart';
import 'package:notex/domain/entities/project.dart';
import 'package:notex/domain/entities/task.dart';
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
import 'package:notex/presentation/pages/task_page.dart';
import 'package:notex/presentation/state/app_state.dart';
import 'package:notex/presentation/state/task_state.dart';
import 'package:notex/presentation/state/theme_state.dart';
import 'package:notex/presentation/state/timer_state.dart';
import 'package:notex/presentation/widgets/app_picker_menu.dart';
import 'package:notex/presentation/widgets/sidebar.dart';
import 'package:notex/presentation/widgets/task_board.dart';

/// Same `_UnusedX`/fake-collaborator pattern as
/// `test/presentation/widgets/task_board_test.dart` — this suite never
/// exercises sync/update/connectivity, only local persistence.
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

class _NoopSyncEngine extends SyncEngine {
  _NoopSyncEngine()
      : super(
          auth: _UnusedAuthRepository(),
          syncService: _UnusedSyncService(),
          connectivity: _UnusedConnectivityService(),
        );

  @override
  Future<void> syncIfAuthenticated() async {}
}

class _UnusedUpdateService implements UpdateService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

class _FakeAuthRepositoryWithStream implements AuthRepository {
  @override
  Stream<bool> get authStateChanges => const Stream<bool>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

/// Widget-level coverage for [TaskPage]'s flat list — brought up to the
/// board card's own task model (status/project/notes/tracked time), and for
/// the two bugs the brief that drove this reported: the task detail
/// dialog's theme mismatch, and the ListTile-inside-a-colored-DecoratedBox
/// ink-splash assertion. Wired to a REAL [TaskState]/[TimerState] backed by
/// an in-memory Drift database, matching `task_board_test.dart`'s
/// established convention.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;
  late TaskState taskState;
  late ThemeState themeState;
  late DriftNoteRepository noteRepository;
  late AppState appState;
  late DriftTimeEntryRepository timeEntryRepository;
  late DriftProjectRepository projectRepository;
  late TimerState timerState;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftTaskRepository(db);
    final transitionUseCase = TransitionTaskStatusUseCase(repository);
    taskState = TaskState(
      createReminder: CreateTaskUseCase(repository),
      getReminders: GetTasksUseCase(repository),
      completeReminder: transitionUseCase,
      updateReminder: UpdateTaskUseCase(repository),
      deleteReminder: DeleteTaskUseCase(repository, _NoopSyncEngine()),
      linkNote: LinkNoteToTaskUseCase(repository),
      unlinkNote: UnlinkNoteFromTaskUseCase(repository),
    );
    themeState = ThemeState();
    GetIt.instance.registerSingleton<TaskState>(taskState);

    noteRepository = DriftNoteRepository(db);
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
        _NoopSyncEngine(),
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
    GetIt.instance.registerSingleton<AppState>(appState);

    GetIt.instance.registerSingleton<ResolveTaskNoteLinkUseCase>(
      ResolveTaskNoteLinkUseCase(noteRepository),
    );

    timeEntryRepository = DriftTimeEntryRepository(db);
    projectRepository = DriftProjectRepository(db);
    timerState = TimerState(
      createProject: CreateProjectUseCase(projectRepository),
      getProjects: GetProjectsUseCase(projectRepository),
      deleteProject: DeleteProjectUseCase(
        projectRepository,
        timeEntryRepository,
        _NoopSyncEngine(),
      ),
      startTimer: StartTimerUseCase(timeEntryRepository, transitionUseCase),
      stopTimer: StopTimerUseCase(timeEntryRepository),
      getEntries: GetTimeEntriesUseCase(timeEntryRepository),
      deleteEntry: DeleteTimeEntryUseCase(timeEntryRepository),
      updateEntry: UpdateTimeEntryUseCase(timeEntryRepository),
      logEntry: LogTimeEntryUseCase(timeEntryRepository),
    );
    GetIt.instance.registerSingleton<TimerState>(timerState);

    GetIt.instance.registerSingleton<GetTimeEntriesUseCase>(
      GetTimeEntriesUseCase(timeEntryRepository),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
    appState.dispose();
    timerState.dispose();
    await db.close();
  });

  Future<void> pumpTaskPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: Listenable.merge([themeState, taskState, timerState]),
        builder: (context, _) => MaterialApp(
          // Mirrors `app.dart`'s own wiring (`theme:
          // widget.themeState.buildTheme()`) so `Theme.of(context)` inside
          // the task detail dialog reflects `themeState.isDarkMode` exactly
          // like production — required for the item-1 theme-colour
          // assertions below. `splashFactory` is overridden the same way
          // `task_board_test.dart`'s `pumpBoard` does, to avoid the
          // splash-shader throw under this test SDK.
          theme: themeState
              .buildTheme()
              .copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: TaskPage(
              appState: appState,
              themeState: themeState,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('nav and page copy — "Reminders" renamed to "Tasks" (item 3)', () {
    testWidgets('the sidebar labels the nav item "Tasks", not "Reminders"',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Sidebar(
              selectedIndex: 0,
              onItemSelected: (_) {},
              accentColor: Colors.blue,
              editorBgColor: const Color(0xFF1A1A2E),
              heroTextColor: Colors.white,
              heroShadows: const [],
              baseIconColor: Colors.white70,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The label only renders as a hover [Tooltip] message, not visible
      // [Text] — same convention every other nav item already uses.
      expect(find.byTooltip('Tasks'), findsOneWidget);
      expect(find.byTooltip('Reminders'), findsNothing);
    });

    testWidgets(
        'the task page header and "New Task" affordance say Tasks, not '
        'Reminders', (tester) async {
      await taskState.initialize();
      await pumpTaskPage(tester);

      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('New Task'), findsOneWidget);
      expect(find.text('Reminders'), findsNothing);
      expect(find.text('New Reminder'), findsNothing);
    });
  });

  group(
      '"New Task" and "Create Task" buttons resolve their foreground from '
      'the accent, not a literal (bug report: washed out against the '
      'accent colour)', () {
    testWidgets(
        "the header's \"New Task\" button's foreground contrasts with the "
        'literal accent colour, not the seed-tinted onPrimary default',
        (tester) async {
      await taskState.initialize();
      await pumpTaskPage(tester);

      final newTaskButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('New Task'),
          matching: find.byType(FilledButton),
        ),
      );
      final expectedForeground =
          themeState.accentColor.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white;

      expect(
        newTaskButton.style?.backgroundColor?.resolve(<WidgetState>{}),
        themeState.accentColor,
      );
      expect(
        newTaskButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        expectedForeground,
        reason: 'left unset, the label resolves against '
            "colorScheme.onPrimary (the seed's tonal primary), not the "
            'literal accentColor used as the background, which is why it '
            'read washed out',
      );
    });

    testWidgets(
        "the empty state's \"Create Task\" button's foreground contrasts "
        'with the literal accent colour, matching the header button\'s own '
        'fix', (tester) async {
      await taskState.initialize();
      await pumpTaskPage(tester);

      final createTaskButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Create Task'),
          matching: find.byType(FilledButton),
        ),
      );
      final expectedForeground =
          themeState.accentColor.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white;

      expect(
        createTaskButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        expectedForeground,
      );
    });
  });

  group('flat list row — brought up to the board card\'s task model (item 4)',
      () {
    testWidgets(
        'a row shows its status, project and linked-notes count, and '
        'tapping it opens the same task detail dialog the board uses',
        (tester) async {
      await projectRepository.save(Project(
        id: 'proj-1',
        name: 'Client work',
        colorValue: 0xFF00FF00,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repository.save(
        Task.create(id: 'r1', title: 'Rich row', scheduledDate: DateTime.now())
            .copyWith(projectId: 'proj-1', noteIds: const ['note-1']),
      );
      await taskState.initialize();
      await timerState.initialize();
      await pumpTaskPage(tester);

      // Status label, project name and notes count all render on the row
      // itself — not only inside the detail dialog.
      expect(find.text('To Do'), findsOneWidget);
      expect(find.text('Client work'), findsOneWidget);
      expect(find.text('1 note'), findsOneWidget);

      // Tapping the row opens the SAME dialog the board card opens
      // (`showTaskDetailDialog`) — proven by the title field it renders.
      await tester.tap(find.text('Rich row'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    });

    testWidgets(
        'a backlog task (no scheduledDate) shows a "Backlog" badge on the '
        'row, not a misleading "Today"', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Someday task'));
      await taskState.initialize();
      await pumpTaskPage(tester);

      expect(find.text('Someday task'), findsOneWidget);
      expect(
        find.text('Backlog'),
        findsOneWidget,
        reason: 'a backlog row must read as "Backlog", not fall back to '
            "today's date",
      );
      expect(find.text('Today'), findsNothing);

      // The home page's own "pending today" bucket must never see it —
      // untouched behavior this change must not regress.
      expect(
        taskState.pendingToday.any((t) => t.title == 'Someday task'),
        isFalse,
      );
    });

    testWidgets(
        'a row with a linked timer shows a live "Tracking" indicator',
        (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Track me'));
      await taskState.initialize();
      await timerState.initialize();
      await pumpTaskPage(tester);

      expect(find.text('Tracking'), findsNothing);

      await timerState.startTimer(taskId: 'r1', description: 'Track me');
      await tester.pumpAndSettle();

      expect(find.text('Tracking'), findsOneWidget);

      await timerState.stopTimer();
    });

    testWidgets(
        'tapping a row does not throw the ListTile-inside-a-colored-'
        'DecoratedBox ink-splash assertion — the row is wrapped in its own '
        'Material (item 2)', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Tap me'));
      await taskState.initialize();
      await pumpTaskPage(tester);

      // The row's ListTile must have a Material ancestor BELOW the
      // decorated (coloured) container it sits in, not only the AlertDialog
      // /Scaffold's Material far above it — otherwise ListTile paints its
      // ink splashes on that distant ancestor, invisible under the
      // DecoratedBox's own background, and Flutter asserts about it in
      // debug mode.
      final listTileFinder = find.ancestor(
        of: find.text('Tap me'),
        matching: find.byType(ListTile),
      );
      expect(listTileFinder, findsOneWidget);
      final materialAncestor = find.ancestor(
        of: listTileFinder,
        matching: find.byType(Material),
      );
      expect(
        materialAncestor,
        findsWidgets,
        reason: 'the ListTile must have its own Material ancestor between '
            'it and the DecoratedBox that colours the row',
      );

      await tester.tap(find.text('Tap me'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'tapping a task row must never throw the ListTile ink-'
            'splash-invisible assertion',
      );
    });
  });

  group('task detail dialog resolves colours from the theme, not a literal '
      '(item 1)', () {
    testWidgets(
        "the dialog's surface is the app's own dark-neutral surface "
        '(ThemeState.editorBgColor), not the ambient seed-tinted '
        'ColorScheme default', (tester) async {
      themeState.toggleDarkMode();
      await repository.save(Task.create(id: 'r1', title: 'Themed dialog'));
      await taskState.initialize();
      await pumpTaskPage(tester);

      await tester.tap(find.text('Themed dialog'));
      await tester.pumpAndSettle();

      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      final expectedSurface = Color.alphaBlend(
        themeState.editorBgColor.withValues(alpha: 0.96),
        Colors.black,
      );
      expect(
        dialog.backgroundColor,
        expectedSurface,
        reason: "the dialog's background must be derived from "
            'ThemeState.editorBgColor — the same surface every other '
            'themed dialog (e.g. TimeEntryEditor) already uses — not left '
            "to AlertDialog's own ColorScheme.fromSeed-derived default",
      );
    });

    testWidgets(
        'no Save/Cancel footer renders — the dialog has no explicit-accent '
        'FilledButton to mismatch in the first place', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Save button'));
      await taskState.initialize();
      await pumpTaskPage(tester);

      await tester.tap(find.text('Save button'));
      await tester.pumpAndSettle();

      // The task detail dialog persists on close (save-on-close) instead
      // of an explicit Save/Cancel footer — see task_board_test.dart's
      // dedicated 'save on close' group for the FilledButton-foreground
      // contrast fix as it now applies to the nested dialogs that DO
      // still carry one (_CreateProjectDialog, the note-in-trash/
      // note-not-found confirmations).
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.actions, isNull);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });
  });

  group(
      'the flat list\'s own "New Task" dialog resolves colours from the '
      'theme too (bug report: off-theme brown surface — this dialog is a '
      'separate, unshared implementation from showAddTaskDialog\'s, so it '
      'was missed in the original sweep)', () {
    testWidgets(
        "the dialog's background is derived from ThemeState.editorBgColor, "
        "and its Create button's foreground contrasts with the literal "
        'accent colour — not the seed-tinted default', (tester) async {
      themeState.toggleDarkMode();
      await taskState.initialize();
      await pumpTaskPage(tester);

      // Default taskViewMode is 'list', so "New Task" opens
      // _showAddReminderDialog, not the (already themed) shared
      // showAddTaskDialog used by the board view.
      await tester.tap(find.text('New Task'));
      await tester.pumpAndSettle();

      final dialogFinder = find.ancestor(
        of: find.text('New Task').last,
        matching: find.byType(AlertDialog),
      );
      final dialog = tester.widget<AlertDialog>(dialogFinder);
      final expectedSurface = Color.alphaBlend(
        themeState.editorBgColor.withValues(alpha: 0.96),
        Colors.black,
      );
      expect(
        dialog.backgroundColor,
        expectedSurface,
        reason: 'this dialog must resolve its background from '
            'ThemeState.editorBgColor, like every other dialog in the app, '
            'not the ambient seed-tinted ColorScheme default',
      );

      final createButton = tester.widget<FilledButton>(
        find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(FilledButton, 'Create'),
        ),
      );
      final expectedForeground =
          themeState.accentColor.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white;
      expect(
        createButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        expectedForeground,
      );
    });
  });

  group('board project filter (item 2)', () {
    Future<void> seedTwoProjectsWithTasks() async {
      await projectRepository.save(Project(
        id: 'proj-a',
        name: 'Project A',
        colorValue: 0xFFFF0000,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await projectRepository.save(Project(
        id: 'proj-b',
        name: 'Project B',
        colorValue: 0xFF0000FF,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repository.save(
        Task.create(id: 'todo-a', title: 'Task A').copyWith(
          projectId: 'proj-a',
        ),
      );
      await repository.save(
        Task.create(id: 'todo-b', title: 'Task B').copyWith(
          projectId: 'proj-b',
        ),
      );
      await repository.save(
        Task.create(id: 'todo-none', title: 'Task No Project'),
      );
      await taskState.initialize();
      await timerState.initialize();
    }

    testWidgets(
        'is hidden in list view and appears once switched to board view, '
        'defaulting to All projects', (tester) async {
      await taskState.initialize();
      await pumpTaskPage(tester);

      expect(
        find.text('All projects'),
        findsNothing,
        reason: 'the board project filter is a board-only affordance — it '
            'must not render in the flat list view',
      );

      await tester.tap(find.byTooltip('Board view'));
      await tester.pumpAndSettle();

      expect(find.text('All projects'), findsOneWidget);
      expect(
        themeState.taskBoardProjectFilter,
        TaskBoard.projectFilterAll,
        reason: 'the filter must default to All projects',
      );
    });

    testWidgets('renders through the shared AppPickerMenu and meets the '
        '44x44 minimum tap target', (tester) async {
      await taskState.initialize();
      await pumpTaskPage(tester);

      await tester.tap(find.byTooltip('Board view'));
      await tester.pumpAndSettle();

      expect(find.byType(AppPickerMenu<String>), findsOneWidget);
      final size = tester.getSize(find.byType(AppPickerMenu<String>));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets(
        'selecting a project narrows the board only — the flat list stays '
        'unfiltered when switching back', (tester) async {
      await seedTwoProjectsWithTasks();
      await pumpTaskPage(tester);

      await tester.tap(find.byTooltip('Board view'));
      await tester.pumpAndSettle();

      // Sanity check: unfiltered, both projects' tasks and the
      // project-less one are all visible on the board.
      expect(find.text('Task A'), findsOneWidget);
      expect(find.text('Task B'), findsOneWidget);
      expect(find.text('Task No Project'), findsOneWidget);

      await tester.tap(find.text('All projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project A').last);
      await tester.pumpAndSettle();

      expect(
        themeState.taskBoardProjectFilter,
        'proj-a',
        reason: 'picking a project must persist the selection',
      );
      expect(find.text('Task A'), findsOneWidget);
      expect(find.text('Task B'), findsNothing);
      expect(find.text('Task No Project'), findsNothing);

      // Switching back to the flat list must show every task again — the
      // board filter is deliberately NOT applied there.
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();

      expect(find.text('Task A'), findsOneWidget);
      expect(find.text('Task B'), findsOneWidget);
      expect(find.text('Task No Project'), findsOneWidget);
    });

    testWidgets('"No Project" filters the board to project-less tasks only',
        (tester) async {
      await seedTwoProjectsWithTasks();
      await pumpTaskPage(tester);

      await tester.tap(find.byTooltip('Board view'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('All projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No Project').last);
      await tester.pumpAndSettle();

      expect(find.text('Task No Project'), findsOneWidget);
      expect(find.text('Task A'), findsNothing);
      expect(find.text('Task B'), findsNothing);
    });

    testWidgets('the selected filter persists across a rebuild of the page',
        (tester) async {
      await seedTwoProjectsWithTasks();
      await pumpTaskPage(tester);

      await tester.tap(find.byTooltip('Board view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project B').last);
      await tester.pumpAndSettle();

      expect(themeState.taskBoardProjectFilter, 'proj-b');

      // Rebuild the whole page fresh (same themeState instance — the
      // persisted-selection contract this mirrors, ThemeState.taskViewMode,
      // is also just held on the object and written to disk on every
      // change; a rebuild here proves the selection outlives the widget
      // tree, not just local State).
      await pumpTaskPage(tester);

      expect(find.text('Project B'), findsOneWidget);
      expect(find.text('Task B'), findsOneWidget);
      expect(find.text('Task A'), findsNothing);
      expect(find.text('Task No Project'), findsNothing);
    });
  });
}
