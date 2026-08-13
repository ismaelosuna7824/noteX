import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
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
import 'package:notex/domain/entities/note.dart';
import 'package:notex/domain/entities/project.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/repositories/auth_repository.dart';
import 'package:notex/domain/services/connectivity_service.dart';
import 'package:notex/domain/services/sync_service.dart';
import 'package:notex/domain/services/update_service.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_note_project_repository.dart';
import 'package:notex/infrastructure/local/drift_note_repository.dart';
import 'package:notex/infrastructure/local/drift_project_repository.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';
import 'package:notex/infrastructure/local/drift_time_entry_repository.dart';
import 'package:notex/presentation/state/app_state.dart';
import 'package:notex/presentation/state/task_state.dart';
import 'package:notex/presentation/state/theme_state.dart';
import 'package:notex/presentation/state/timer_state.dart';
import 'package:notex/presentation/widgets/task_board.dart';

/// Minimal fakes satisfying [SyncEngine]'s collaborators — this suite never
/// exercises sync, only local persistence. Same pattern as
/// delete_task_use_case_test.dart's `_UnusedAuthRepository` and friends:
/// every unused member throws, so an accidental new call site is caught
/// immediately instead of silently no-op'ing.
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

/// A [SyncEngine] that no-ops `syncIfAuthenticated` — [DeleteTaskUseCase] is
/// wired into [TaskState] but never exercised by this board-focused suite.
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

/// Same `_UnusedX` pattern as the fakes above, but with one concrete
/// override: [AppState]'s constructor subscribes to [authStateChanges]
/// directly (`_authRepository.authStateChanges.listen(...)`), so unlike the
/// other unused members it cannot be left to `noSuchMethod` — that would
/// throw during construction, before any test body runs.
class _FakeAuthRepositoryWithStream implements AuthRepository {
  @override
  Stream<bool> get authStateChanges => const Stream<bool>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

/// Spies on [TransitionTaskStatusUseCase.execute] without changing its
/// behavior — delegates to the real implementation, so persistence still
/// happens exactly as it would in the app. Pins the drag-to-column gesture
/// to this specific use case: if a future shortcut (e.g. a card `onTap`)
/// wrote status some other way, [calls] would stay empty while the
/// persisted row still changed, failing the assertion loudly.
class _SpyTransitionUseCase extends TransitionTaskStatusUseCase {
  _SpyTransitionUseCase(super.repository);

  final List<(String taskId, TaskStatus next)> calls = [];

  @override
  Future<Task?> execute(String taskId, TaskStatus next) async {
    calls.add((taskId, next));
    return super.execute(taskId, next);
  }
}

/// Widget-level coverage for [TaskBoard] — the only genuinely new
/// user-facing surface in the task-tracker change, and drag-to-transition
/// is its riskiest interaction. Wired to a REAL [TaskState] backed by a
/// real in-memory Drift database — the same `AppDatabase.forTesting`
/// pattern `drift_task_repository_test.dart` and
/// `delete_task_use_case_test.dart` already use — rather than mocks, so
/// these tests exercise the actual query/transition contracts the board
/// depends on, not a stand-in for them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftTaskRepository repository;
  late _SpyTransitionUseCase transitionSpy;
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
    transitionSpy = _SpyTransitionUseCase(repository);
    taskState = TaskState(
      createReminder: CreateTaskUseCase(repository),
      getReminders: GetTasksUseCase(repository),
      completeReminder: transitionSpy,
      updateReminder: UpdateTaskUseCase(repository),
      deleteReminder: DeleteTaskUseCase(repository, _NoopSyncEngine()),
      linkNote: LinkNoteToTaskUseCase(repository),
      unlinkNote: UnlinkNoteFromTaskUseCase(repository),
    );
    themeState = ThemeState();

    // The note-linking affordance (_TaskDetailDialog._linkNote) reads
    // GetIt.instance<AppState>().notes — a REAL AppState, backed by the
    // same in-memory database as the task repository above, sharing the
    // note-project use cases it wraps. Note-project/update/cleanup paths
    // are never exercised by this suite; only checkForUpdate's own
    // UpdateService is a throwing fake, since AppState never calls it
    // unless `checkForUpdate()`/`initialize()` is invoked, which this
    // suite deliberately avoids (it seeds notes directly and calls the
    // narrower `refreshNotes()`).
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

    // The linked-notes list (_TaskDetailDialog._loadLinkedNotes/_openNote)
    // resolves each note through ResolveTaskNoteLinkUseCase (design D9) —
    // a REAL instance over the same in-memory note repository, so a task
    // with a trashed or missing link exercises the actual three-state
    // resolution rather than a stand-in for it.
    GetIt.instance.registerSingleton<ResolveTaskNoteLinkUseCase>(
      ResolveTaskNoteLinkUseCase(noteRepository),
    );

    // The "Start timer" button (_TaskDetailDialog._startTimer) resolves
    // TimerState via GetIt.instance<TimerState>() — a REAL TimerState, over
    // the same in-memory database, so the button exercises the actual
    // StartTimerUseCase -> TransitionTaskStatusUseCase chain rather than a
    // stand-in for it. Registering it here also means: if this registration
    // were ever missing (as it is in production the moment the app's own
    // injection.dart forgets it), GetIt would throw synchronously inside the
    // button's onPressed and the failure would surface as a widget-test
    // error instead of a silent no-op click.
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
      startTimer: StartTimerUseCase(timeEntryRepository, transitionSpy),
      stopTimer: StopTimerUseCase(timeEntryRepository),
      getEntries: GetTimeEntriesUseCase(timeEntryRepository),
      deleteEntry: DeleteTimeEntryUseCase(timeEntryRepository),
      updateEntry: UpdateTimeEntryUseCase(timeEntryRepository),
      logEntry: LogTimeEntryUseCase(timeEntryRepository),
    );
    GetIt.instance.registerSingleton<TimerState>(timerState);

    // The task detail dialog's "total tracked time" figure
    // (_TaskDetailDialog._loadTimeEntries) resolves
    // GetIt.instance<GetTimeEntriesUseCase>().getByTaskId(...) — a REAL
    // instance over the same in-memory database, mirroring every other
    // GetIt.instance<UseCase>() call site in this dialog.
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

  Future<void> pumpBoard(WidgetTester tester) async {
    // The redesigned task detail dialog is taller/wider than the default
    // 800x600 test surface can host without a false layout overflow — this
    // app is desktop-first (sdd-init), so a generous window size here
    // reflects real usage, not a test-only workaround for an actual
    // overflow bug.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        // Avoids the splash-shader throw under this test SDK — same trick
        // mention_picker_host_test.dart uses.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 700,
            child: AnimatedBuilder(
              animation: Listenable.merge([taskState, timerState]),
              builder: (context, _) => TaskBoard(
                taskState: taskState,
                themeState: themeState,
                timerState: timerState,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Drags the card titled [title] onto the column at [columnIndex] (Todo=0,
  /// Doing=1, Blocked=2, Done=3 — [TaskBoard]'s fixed column order). Moves in
  /// two steps so the drag exceeds touch slop and wins the gesture arena over
  /// the card's own [InkWell] tap recognizer.
  Future<void> dragCardToColumn(
    WidgetTester tester,
    String title,
    int columnIndex,
  ) async {
    final cardCenter = tester.getCenter(find.text(title));
    final columnCenter =
        tester.getCenter(find.byType(DragTarget<Task>).at(columnIndex));

    final gesture = await tester.startGesture(cardCenter);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(columnCenter);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('backlog — never leaks into the daily list (spec #561)', () {
    testWidgets(
        'a task created with "No date (add to backlog)" checked never '
        'appears in pendingToday, and shows a Backlog chip on the board',
        (tester) async {
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Someday task',
      );
      await tester.tap(find.text('No date (add to backlog)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // The leak the spec forbids: a null-scheduledDate task must never
      // reach the daily list the home card and flat list both read from.
      expect(
        taskState.pendingToday.any((t) => t.title == 'Someday task'),
        isFalse,
        reason: 'a backlog task must never appear in the daily/today list',
      );
      // The board itself must be able to show it was created (in Todo, the
      // default status), distinguished by a Backlog chip rather than a date.
      expect(find.text('Someday task'), findsOneWidget);
      expect(find.text('Backlog'), findsOneWidget);
    });
  });

  group('blocked — own bucket, does not carry into the daily list', () {
    testWidgets(
        'a blocked task (even with a past scheduledDate) leaves pendingToday '
        'and appears only in the Blocked column', (tester) async {
      await repository.save(Task.create(
        id: 'r1',
        title: 'Overdue but blocked',
        scheduledDate: DateTime.now().subtract(const Duration(days: 3)),
      ));

      await taskState.initialize();
      expect(
        taskState.pendingToday.map((t) => t.id),
        contains('r1'),
        reason: 'sanity check: starts out carrying over as pending',
      );

      await pumpBoard(tester);
      await dragCardToColumn(tester, 'Overdue but blocked', 2); // Blocked

      expect(
        taskState.pendingToday.any((t) => t.id == 'r1'),
        isFalse,
        reason: 'blocked must not carry into the daily list',
      );
      expect(
        taskState.blocked.map((t) => t.id),
        contains('r1'),
        reason: 'blocked gets its own bucket',
      );
    });
  });

  group('done — stays visible for the day it was scheduled', () {
    testWidgets(
        'a task scheduled today, marked done, stays on the board dimmed '
        'and struck through (not removed)', (tester) async {
      await repository.save(Task.create(
        id: 'r1',
        title: 'Finish report',
        scheduledDate: DateTime.now(),
      ));
      await taskState.initialize();
      await pumpBoard(tester);

      await dragCardToColumn(tester, 'Finish report', 3); // Done

      expect(find.text('Finish report'), findsOneWidget);
      final titleWidget =
          tester.widget<Text>(find.text('Finish report'));
      expect(
        titleWidget.style?.decoration,
        TextDecoration.lineThrough,
        reason: 'a done card renders struck through, not just moved',
      );

      // The other half of "visible until end of day, gone after rollover" —
      // simulating a real day rollover needs a controllable clock, which
      // Task/TaskState do not have (every timestamp is DateTime.now()).
      // That half is covered where it actually is testable: repository
      // level, in getCompletedOn's "excludes a done task scheduled on a
      // different day" test (drift_task_repository_test.dart, batch 7).
    });
  });

  group('blockedReason — display scoped to blocked, data never destroyed',
      () {
    testWidgets(
        'renders while blocked, disappears from the card after leaving '
        'blocked, but the text survives underneath', (tester) async {
      await repository.save(Task.create(
        id: 'r1',
        title: 'Needs review',
        scheduledDate: DateTime.now(),
      ));
      await taskState.initialize();
      await pumpBoard(tester);

      await dragCardToColumn(tester, 'Needs review', 2); // -> blocked

      await tester.tap(find.text('Needs review'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Blocked reason'),
        'waiting on legal',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Rendered while blocked.
      expect(find.text('waiting on legal'), findsOneWidget);

      await dragCardToColumn(tester, 'Needs review', 1); // -> doing

      // Scoped: gone from the card the moment status leaves blocked.
      expect(find.text('waiting on legal'), findsNothing);
      // Retained: the underlying data was never cleared by the transition.
      final persisted = await repository.getById('r1');
      expect(persisted!.blockedReason, 'waiting on legal',
          reason: 'a transition must never destroy user-authored text');
    });
  });

  group('note linking — N notes per task, visible '
      '(decision architecture/task-note-linking-model)', () {
    testWidgets(
        'tapping "Link note", picking a note from the picker, appends it to '
        'the task\'s noteIds, shows it in the linked-notes list, and keeps '
        'the dialog open', (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Meeting notes',
        content: 'agenda',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await appState.refreshNotes();

      await repository.save(Task.create(id: 'r1', title: 'Unlinked task'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Unlinked task'));
      await tester.pumpAndSettle();

      // Before linking: nothing to open, only the affordance to link.
      expect(find.text('Link note'), findsOneWidget);
      expect(find.text('Meeting notes'), findsNothing);

      await tester.tap(find.text('Link note'));
      await tester.pumpAndSettle();

      // The picker dialog is open, listing the seeded note.
      expect(find.text('Link a note'), findsOneWidget);
      expect(find.text('Meeting notes'), findsOneWidget);

      await tester.tap(find.text('Meeting notes'));
      await tester.pumpAndSettle();

      // Persisted through LinkNoteToTaskUseCase — must not touch status.
      final persisted = await repository.getById('r1');
      expect(persisted!.noteIds, ['note-1']);
      expect(
        persisted.status,
        TaskStatus.todo,
        reason: 'linking a note must not touch status (design D3 — only '
            'transitionTo may write it)',
      );

      // Dialog stays open (does not pop) and now shows the linked note's
      // title plus an affordance to link another — no need to reopen the
      // card to see the result of the action just taken.
      expect(find.text('Meeting notes'), findsOneWidget);
      expect(find.text('Link another note'), findsOneWidget);
      expect(find.text('Link note'), findsNothing);
    });

    testWidgets(
        'linking a second note appends it — the first stays linked, '
        'not replaced', (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Meeting notes',
        content: '',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await noteRepository.save(Note(
        id: 'note-2',
        title: 'Design doc',
        content: '',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      ));
      await appState.refreshNotes();

      await repository.save(
        Task.create(id: 'r1', title: 'Task with links')
            .copyWith(noteIds: const ['note-1']),
      );
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Task with links'));
      await tester.pumpAndSettle();

      expect(find.text('Meeting notes'), findsOneWidget);

      await tester.tap(find.text('Link another note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Design doc'));
      await tester.pumpAndSettle();

      // Both rendered — the first was never replaced.
      expect(find.text('Meeting notes'), findsOneWidget);
      expect(find.text('Design doc'), findsOneWidget);

      final persisted = await repository.getById('r1');
      expect(persisted!.noteIds, ['note-1', 'note-2']);
    });

    testWidgets(
        'unlinking one note leaves the others linked', (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Meeting notes',
        content: '',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await noteRepository.save(Note(
        id: 'note-2',
        title: 'Design doc',
        content: '',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      ));
      await appState.refreshNotes();

      await repository.save(
        Task.create(id: 'r1', title: 'Task with links').copyWith(
          noteIds: const ['note-1', 'note-2'],
        ),
      );
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Task with links'));
      await tester.pumpAndSettle();

      expect(find.text('Meeting notes'), findsOneWidget);
      expect(find.text('Design doc'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.close).first);
      await tester.pumpAndSettle();

      // Exactly one row removed — the other remains.
      expect(find.text('Design doc'), findsOneWidget);

      final persisted = await repository.getById('r1');
      expect(persisted!.noteIds, hasLength(1));
    });

    testWidgets(
        'the board card shows a count indicator when the task carries '
        'linked notes', (tester) async {
      await repository.save(
        Task.create(id: 'r1', title: 'Documented task').copyWith(
          noteIds: const ['note-1', 'note-2'],
        ),
      );
      await repository.save(Task.create(id: 'r2', title: 'Bare task'));
      await taskState.initialize();
      await pumpBoard(tester);

      expect(find.text('2 notes'), findsOneWidget);
      // The task with no links shows no count at all.
      expect(find.text('0 notes'), findsNothing);
    });

    testWidgets(
        'a task with a trashed note still renders its other, live notes '
        'normally', (tester) async {
      await noteRepository.save(Note(
        id: 'note-live',
        title: 'Still here',
        content: '',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await noteRepository.save(Note(
        id: 'note-trashed',
        title: 'In the trash',
        content: '',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
        deletedAt: DateTime(2026, 1, 3),
      ));
      await appState.refreshNotes();

      await repository.save(
        Task.create(id: 'r1', title: 'Task with a trashed link').copyWith(
          noteIds: const ['note-live', 'note-trashed'],
        ),
      );
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Task with a trashed link'));
      await tester.pumpAndSettle();

      // The live note renders its own title normally...
      expect(find.text('Still here'), findsOneWidget);
      // ...while the trashed one is labeled distinctly, not silently
      // dropped from the list and not crashing the dialog.
      expect(find.textContaining('in trash'), findsOneWidget);
    });

    testWidgets('the picker search field filters the note list by title',
        (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Meeting notes',
        content: '',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await noteRepository.save(Note(
        id: 'note-2',
        title: 'Grocery list',
        content: '',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      ));
      await appState.refreshNotes();

      await repository.save(Task.create(id: 'r1', title: 'Unlinked task'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Unlinked task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link note'));
      await tester.pumpAndSettle();

      expect(find.text('Meeting notes'), findsOneWidget);
      expect(find.text('Grocery list'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search notes…'),
        'grocery',
      );
      await tester.pumpAndSettle();

      expect(find.text('Meeting notes'), findsNothing);
      expect(find.text('Grocery list'), findsOneWidget);
    });

    testWidgets(
        'a trashed note is excluded from the picker, mirroring '
        'MentionPickerHost.mentionCandidates', (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Trashed note',
        content: '',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        deletedAt: DateTime(2026, 1, 2),
      ));
      await appState.refreshNotes();

      await repository.save(Task.create(id: 'r1', title: 'Unlinked task'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Unlinked task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link note'));
      await tester.pumpAndSettle();

      expect(find.text('Trashed note'), findsNothing);
      expect(find.text('No notes found'), findsOneWidget);
    });
  });

  group('backlog task dragged to Done — regression for the vanishing gap',
      () {
    testWidgets(
        'a backlog task (no scheduledDate) marked done still appears in the '
        'Done column instead of disappearing from the board', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Someday, done'));
      await taskState.initialize();
      await pumpBoard(tester);

      await dragCardToColumn(tester, 'Someday, done', 3); // Done

      // getCompletedOn is date-scoped and a backlog task has no date, so
      // without the union added in TaskBoard._tasksFor this card would
      // vanish from every column the moment it's marked done — invisible
      // until it was found, and exactly the kind of thing a refactor could
      // silently reintroduce.
      expect(find.text('Someday, done'), findsOneWidget);
    });
  });

  group('drag issues a transition through TransitionTaskStatusUseCase', () {
    testWidgets(
        'dragging a card to another column calls the sole transition use '
        'case exactly once, and the persisted status matches what it '
        'recorded', (tester) async {
      await repository.save(Task.create(
        id: 'r1',
        title: 'Ship it',
        scheduledDate: DateTime.now(),
      ));
      await taskState.initialize();
      await pumpBoard(tester);

      await dragCardToColumn(tester, 'Ship it', 1); // -> doing

      expect(transitionSpy.calls, [('r1', TaskStatus.doing)]);
      final persisted = await repository.getById('r1');
      expect(
        persisted!.status,
        TaskStatus.doing,
        reason: 'the persisted status must match what the spied use case '
            'recorded — proving the change flowed through it, not around '
            'it',
      );
    });
  });

  group('"Start timer" / "Stop" control in the task detail dialog', () {
    testWidgets(
        'tapping "Start timer" persists a running TimeEntry linked to the '
        'task, transitions the task to doing, and keeps the dialog open '
        'showing "Stop" — controlling the timer from here, not '
        'fire-and-forget', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Track me'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Track me'));
      await tester.pumpAndSettle();

      expect(find.text('Start timer'), findsOneWidget);
      await tester.tap(find.text('Start timer'));
      await tester.pumpAndSettle();

      final running = await timeEntryRepository.getRunning();
      expect(
        running,
        isNotNull,
        reason: 'clicking "Start timer" must persist a running TimeEntry',
      );
      expect(running!.taskId, 'r1');
      expect(running.description, 'Track me');

      expect(transitionSpy.calls, [('r1', TaskStatus.doing)]);
      final persisted = await repository.getById('r1');
      expect(persisted!.status, TaskStatus.doing);

      // The dialog stays open — settled decision: the user asked to
      // control the timer from here, so the dialog no longer pops on
      // start; the control itself switches to "Stop".
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Start timer'), findsNothing);

      // Feedback gap fix retained: the board card itself also shows a
      // running timer indicator — closing the "the dialog just closes and
      // the user has no way to know a clock started" gap named in the
      // original bug report.
      expect(
        find.byIcon(Icons.timer_rounded),
        findsOneWidget,
        reason: 'the task card must show a running-timer indicator once '
            'the timer starts',
      );

      await timerState.stopTimer();
    });

    testWidgets(
        'tapping "Stop" ends the running entry and switches the control '
        'back to "Start timer"', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Track me'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Track me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start timer'));
      await tester.pumpAndSettle();

      expect(find.text('Stop'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(find.text('Start timer'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);

      final running = await timeEntryRepository.getRunning();
      expect(running, isNull, reason: '"Stop" must end the running entry');
    });

    testWidgets(
        'total tracked time accumulates across multiple start/stop '
        'stretches, not just the currently running one', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Multi session'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Multi session'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      var entries = await timeEntryRepository.getByTaskId('r1');
      expect(entries, hasLength(1));
      expect(entries.single.isRunning, isFalse);

      await tester.tap(find.text('Start timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Two separate stretches persisted, not one entry overwritten —
      // "pause" in this app means starting a fresh TimeEntry, never
      // collapsing gaps into one fictitious span (settled decision).
      entries = await timeEntryRepository.getByTaskId('r1');
      expect(entries, hasLength(2));
      expect(entries.every((e) => !e.isRunning), isTrue);

      // The dialog surfaces a running total reflecting every stretch — the
      // exact duration is untestable without a controllable clock (named,
      // not faked, matching this suite's own established convention), but
      // the label itself must be present and must have re-rendered after
      // the second stretch was persisted.
      expect(find.textContaining('Total'), findsOneWidget);
    });
  });

  group('task <-> timer project link', () {
    testWidgets(
        'starting a timer from the dialog persists the entry with the '
        "task's assigned project — inherits it, doesn't use the timer "
        "bar's own draft project", (tester) async {
      await projectRepository.save(Project(
        id: 'proj-1',
        name: 'Client work',
        colorValue: 0xFF00FF00,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repository.save(
        Task.create(id: 'r1', title: 'Track me').copyWith(
          projectId: 'proj-1',
        ),
      );
      await taskState.initialize();
      await timerState.initialize();
      // The draft bar has its own, different project selected — proving
      // the entry inherits the TASK's project, not the draft's.
      timerState.setDraftProject('some-other-draft-project');
      await pumpBoard(tester);

      await tester.tap(find.text('Track me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start timer'));
      await tester.pumpAndSettle();

      final running = await timeEntryRepository.getRunning();
      expect(running!.projectId, 'proj-1');

      await timerState.stopTimer();
    });

    testWidgets(
        'a task pointing at a deleted project still opens its dialog '
        'without crashing, degrading the display rather than breaking it',
        (tester) async {
      final deletedProject = Project(
        id: 'proj-gone',
        name: 'Old client',
        colorValue: 0xFF0000FF,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ).markDeleted();
      await projectRepository.save(deletedProject);
      await repository.save(
        Task.create(id: 'r1', title: 'Orphaned project task').copyWith(
          projectId: 'proj-gone',
        ),
      );
      await taskState.initialize();
      await timerState.initialize();
      await pumpBoard(tester);

      // Must render the board and open the dialog without throwing.
      expect(find.text('Orphaned project task'), findsOneWidget);
      await tester.tap(find.text('Orphaned project task'));
      await tester.pumpAndSettle();

      // Degrades the display, keeps the data — mirrors the trashed-note
      // affordance precedent — rather than clearing the dangling link or
      // crashing the dropdown.
      expect(find.textContaining('Deleted project'), findsOneWidget);
      final persisted = await repository.getById('r1');
      expect(persisted!.projectId, 'proj-gone',
          reason: 'a since-deleted project reference must not be silently '
              'cleared');
    });

    testWidgets(
        'picking a project from the selector persists it onto the task '
        'without touching status', (tester) async {
      await projectRepository.save(Project(
        id: 'proj-1',
        name: 'Client work',
        colorValue: 0xFF00FF00,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repository.save(Task.create(id: 'r1', title: 'Unassigned task'));
      await taskState.initialize();
      await timerState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Unassigned task'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Client work').last);
      await tester.pumpAndSettle();

      final persisted = await repository.getById('r1');
      expect(persisted!.projectId, 'proj-1');
      expect(
        persisted.status,
        TaskStatus.todo,
        reason: 'a project change must never touch status (design D3)',
      );
    });
  });

  group('running-timer indicator on the board card — feedback gap fix', () {
    testWidgets(
        'the indicator is scoped to the linked task and disappears when '
        'the timer stops', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Tracked'));
      await repository.save(Task.create(id: 'r2', title: 'Not tracked'));
      await taskState.initialize();
      await pumpBoard(tester);

      expect(find.byIcon(Icons.timer_rounded), findsNothing);

      await tester.tap(find.text('Tracked'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start timer'));
      await tester.pumpAndSettle();

      // Exactly one card shows the indicator — the linked task's, not the
      // unrelated one's.
      expect(find.byIcon(Icons.timer_rounded), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Tracked'),
            matching: find.byType(Container),
          ),
          matching: find.byIcon(Icons.timer_rounded),
        ),
        findsWidgets,
        reason: 'the running indicator belongs to the linked task\'s card',
      );

      await timerState.stopTimer();
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.timer_rounded),
        findsNothing,
        reason: 'stopping the timer must remove the indicator',
      );
    });
  });

  group('task detail dialog — redesigned layout', () {
    testWidgets(
        'the notes list is bounded to a whole number of rows and shows a '
        'scrollbar affordance once it overflows, instead of clipping a row '
        'mid-height', (tester) async {
      await repository.save(
        Task.create(id: 'r1', title: 'Many notes').copyWith(
          noteIds: const ['n1', 'n2', 'n3', 'n4', 'n5'],
        ),
      );
      for (var i = 1; i <= 5; i++) {
        await noteRepository.save(Note(
          id: 'n$i',
          title: 'Note $i',
          content: '',
          createdAt: DateTime(2026, 1, i),
          updatedAt: DateTime(2026, 1, i),
        ));
      }
      await appState.refreshNotes();
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Many notes'));
      await tester.pumpAndSettle();

      // The section header surfaces the count up front (rendered uppercase
      // as part of the muted small-caps section-header style).
      expect(find.text('NOTES · 5'), findsOneWidget);

      // The scrollable list area's own height must be an exact multiple of
      // a single row's height — the structural guarantee that a row is
      // never cut mid-way, only ever between rows. Each row carries its own
      // ValueKey (list-state-preservation convention), which doubles as a
      // stable finder here.
      final listHeight = tester.getSize(find.byType(ListView).first).height;
      final rowHeight = tester.getSize(find.byKey(const ValueKey('n1'))).height;
      expect(
        listHeight % rowHeight,
        closeTo(0, 0.5),
        reason: 'the notes list viewport must cut between rows, not '
            'through one',
      );

      // With 5 notes overflowing the bounded viewport, an explicit "there
      // is more" affordance (a visible scrollbar) must be present.
      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(
        scrollbar.thumbVisibility,
        isTrue,
        reason: 'an overflowing notes list must show an unmistakable '
            '"there is more" affordance',
      );
    });

    testWidgets(
        'the notes scrollbar shares its list\'s ScrollController, so a '
        'desktop target platform does not assert on every frame',
        (tester) async {
      // Regression test for a bug that reached the running app.
      //
      // A vertical ScrollView attaches itself to the PrimaryScrollController
      // by default ONLY on mobile platforms. flutter_test defaults to a
      // mobile platform, so a controller-less Scrollbar happens to find a
      // ScrollPosition here and passes — while on macOS it finds none and
      // throws "The Scrollbar's ScrollController has no ScrollPosition
      // attached" on every frame the thumb is visible.
      //
      // The platform override is the whole point of this test: without it,
      // it cannot fail. It must be restored inside the body — the framework
      // asserts that no foundation debug variable is left changed, and that
      // check runs before any addTearDown callback.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      Object? caught;
      try {
        await repository.save(
          Task.create(id: 'r1', title: 'Desktop notes').copyWith(
            noteIds: const ['n1', 'n2', 'n3', 'n4', 'n5'],
          ),
        );
        for (var i = 1; i <= 5; i++) {
          await noteRepository.save(Note(
            id: 'n$i',
            title: 'Note $i',
            content: '',
            createdAt: DateTime(2026, 1, i),
            updatedAt: DateTime(2026, 1, i),
          ));
        }
        await appState.refreshNotes();
        await taskState.initialize();
        await pumpBoard(tester);

        await tester.tap(find.text('Desktop notes'));
        await tester.pumpAndSettle();
        caught = tester.takeException();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }

      expect(
        caught,
        isNull,
        reason: 'the Scrollbar must be driven by the same ScrollController as '
            'its ListView — on desktop there is no PrimaryScrollController to '
            'fall back to',
      );
    });

    testWidgets(
        'a broken note link (note not found) renders a visually distinct, '
        'de-emphasised row instead of looking like a normal note',
        (tester) async {
      await repository.save(
        Task.create(id: 'r1', title: 'Task with dead link').copyWith(
          noteIds: const ['ghost-note'],
        ),
      );
      await appState.refreshNotes();
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Task with dead link'));
      await tester.pumpAndSettle();

      expect(find.text('Note not found'), findsOneWidget);

      // Distinct treatment must not rely on colour alone — italic style is
      // an independent signal alongside the muted/warning colour.
      final label = tester.widget<Text>(find.text('Note not found'));
      expect(
        label.style?.fontStyle,
        FontStyle.italic,
        reason: 'a broken link must read as visually distinct from a '
            'normal note row, not just differently coloured',
      );

      // The fix is offered inline via a distinctly labelled remove action.
      expect(find.byTooltip('Remove broken link'), findsOneWidget);
    });

    testWidgets(
        'the timer control sits with the task, separated from the '
        'Cancel/Save dialog actions row', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Separate me'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Separate me'));
      await tester.pumpAndSettle();

      // The AlertDialog's own actions row holds only Cancel and Save now —
      // the timer control was lifted out of it.
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(
        dialog.actions,
        hasLength(2),
        reason: 'Cancel/Save act on the dialog; the timer acts on the '
            'task — they must not share the same actions row',
      );

      // The timer control renders above the footer, inside the task
      // section, not inline with Cancel/Save.
      final timerY = tester.getTopLeft(find.text('Start timer')).dy;
      final cancelY = tester.getTopLeft(find.text('Cancel')).dy;
      expect(
        timerY,
        lessThan(cancelY),
        reason: 'the timer control must sit above the footer, grouped '
            'with the task rather than the dialog actions',
      );
    });

    testWidgets('the title field has a visible label, not just a hint',
        (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Label me'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Label me'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, 'Title'),
        findsOneWidget,
        reason: 'the title field must carry a visible label, not rely on '
            'placeholder-only text',
      );
    });
  });
}
