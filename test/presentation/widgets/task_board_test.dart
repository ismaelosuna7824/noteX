import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:notex/presentation/widgets/markdown/notex_markdown_view.dart';
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

/// An [UpdateTaskUseCase] that always throws — proves the task detail
/// dialog's save-on-close surfaces a failure (SnackBar) rather than
/// swallowing it. There is no Cancel to fall back on once Save/Cancel are
/// gone, so silence would mean the user's edit vanished without a trace.
class _ThrowingUpdateTaskUseCase extends UpdateTaskUseCase {
  _ThrowingUpdateTaskUseCase(super.repository);

  @override
  Future<Task?> execute(
    String taskId, {
    String? title,
    String? description,
    Object? scheduledDate,
    Object? blockedReason,
    Object? projectId,
  }) async {
    throw StateError('simulated save failure');
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

    // "New note" (_TaskDetailDialog._createLinkedNote) and the note
    // editor/preview modal's own save path (_NoteEditorDialogState._flush)
    // resolve CreateNoteUseCase/UpdateNoteUseCase via GetIt directly — REAL
    // instances over the same in-memory note repository as [appState]'s own
    // (registered separately here, mirroring [updateNoteUseCase] above),
    // never a stand-in, and never through AppState's own wrapped verbs.
    GetIt.instance.registerSingleton<CreateNoteUseCase>(
      CreateNoteUseCase(noteRepository),
    );
    GetIt.instance.registerSingleton<UpdateNoteUseCase>(updateNoteUseCase);

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

  Future<void> pumpBoard(WidgetTester tester, {TaskState? overrideTaskState}) async {
    // The redesigned task detail dialog is taller/wider than the default
    // 800x600 test surface can host without a false layout overflow — this
    // app is desktop-first (sdd-init), so a generous window size here
    // reflects real usage, not a test-only workaround for an actual
    // overflow bug.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final boardTaskState = overrideTaskState ?? taskState;
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: Listenable.merge([themeState, boardTaskState, timerState]),
        builder: (context, _) => MaterialApp(
          // Mirrors `app.dart`'s own wiring (`theme:
          // widget.themeState.buildTheme()`) so `Theme.of(context)` inside
          // the task detail dialog (and the nested dialogs it opens)
          // reflects `themeState.isDarkMode` exactly like production —
          // required for any test asserting theme-derived colours.
          // `splashFactory` is overridden the same way this helper always
          // has, to avoid the splash-shader throw under this test SDK.
          theme: themeState
              .buildTheme()
              .copyWith(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: TaskBoard(
                taskState: boardTaskState,
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
      // Save-on-close (no explicit Save button anymore): the header X is
      // one of the three ways to close, all persisting identically — see
      // the dedicated 'save on close' group below.
      await tester.tap(find.byTooltip('Close'));
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

  group(
      'notes section — create and preview a note as MODALS, rendered by '
      'default (settled decision: "para crear la nota estaría bien que '
      'fuera un modal ... y para el preview también ... ya renderizada")',
      () {
    testWidgets(
        '"New note" creates a note, links it to the task in one gesture, '
        'and opens a MODAL that is immediately writable (empty note '
        'downgrades preview to edit)', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Blank task'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Blank task'));
      await tester.pumpAndSettle();

      // Before creating: only the "New note"/"Link note" pair, and just the
      // task dialog itself — no note modal yet.
      expect(find.text('New note'), findsOneWidget);
      expect(find.byKey(const Key('task-note-preview')), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();

      // The task dialog never closed — its own Title field is still in the
      // tree, layered BEHIND the note modal that just opened on top of it.
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
      expect(
        find.byType(AlertDialog),
        findsNWidgets(2),
        reason: 'creating a note opens its own modal on top of the task '
            'dialog, not an inline takeover of the NOTES section',
      );

      // A brand-new note is empty, so the preview-by-default surface
      // downgrades to the plain edit field automatically — ready to type,
      // not rendering nothing.
      final previewField = find.descendant(
        of: find.byKey(const Key('task-note-preview')),
        matching: find.byType(TextField),
      );
      expect(previewField, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('task-note-preview')),
          matching: find.byType(NoteXMarkdownView),
        ),
        findsNothing,
      );

      await tester.enterText(previewField, 'Written from the task');
      await tester.tap(find.byTooltip('Close note'));
      await tester.pumpAndSettle();

      // The modal closed — back to just the task dialog.
      expect(find.byType(AlertDialog), findsOneWidget);

      // Persisted through CreateNoteUseCase + LinkNoteToTaskUseCase —
      // noteIds grew by exactly one, and the new note itself carries the
      // content typed while still inside the task dialog's own flow.
      final persisted = await repository.getById('r1');
      expect(persisted!.noteIds, hasLength(1));
      final note = await noteRepository.getById(persisted.noteIds.first);
      expect(note!.content, 'Written from the task');
    });

    testWidgets(
        'previewing a linked note WITH content opens a MODAL showing it '
        'RENDERED, not the source TextField', (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Meeting notes',
        content: '# Agenda\n\n- item one\n- item two',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await appState.refreshNotes();
      await repository.save(
        Task.create(id: 'r1', title: 'Has a note').copyWith(
          noteIds: const ['note-1'],
        ),
      );
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Has a note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meeting notes'));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsNWidgets(2),
        reason: 'previewing a linked note opens its own modal on top of '
            'the task dialog',
      );

      // Rendered, not source: the preview container hosts the Markdown
      // renderer, and no editable TextField for it.
      expect(
        find.descendant(
          of: find.byKey(const Key('task-note-preview')),
          matching: find.byType(NoteXMarkdownView),
        ),
        findsOneWidget,
        reason: 'a note with content must open already rendered — "que se '
            'vea el md bien, y no en modo código"',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('task-note-preview')),
          matching: find.byType(TextField),
        ),
        findsNothing,
        reason: 'rendered preview must not show the raw Markdown source '
            'TextField',
      );
    });

    testWidgets(
        "the editor's edit⇄preview toggle still switches to editing from "
        'the preview modal, and edits persist through the note\'s own '
        'path (UpdateNoteUseCase) without marking the task dirty',
        (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Meeting notes',
        content: 'original',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await appState.refreshNotes();
      await repository.save(
        Task.create(id: 'r1', title: 'Has a note').copyWith(
          noteIds: const ['note-1'],
        ),
      );
      await taskState.initialize();
      final before = await repository.getById('r1');
      await pumpBoard(tester);

      await tester.tap(find.text('Has a note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meeting notes'));
      await tester.pumpAndSettle();

      // Opens rendered first (settled contract, asserted above).
      expect(
        find.descendant(
          of: find.byKey(const Key('task-note-preview')),
          matching: find.byType(NoteXMarkdownView),
        ),
        findsOneWidget,
      );

      // Toggle back to editing — the editor's own edit⇄preview control,
      // never disabled from this modal.
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      final previewField = find.descendant(
        of: find.byKey(const Key('task-note-preview')),
        matching: find.byType(TextField),
      );
      expect(previewField, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('task-note-preview')),
          matching: find.byType(NoteXMarkdownView),
        ),
        findsNothing,
      );

      await tester.enterText(previewField, 'edited from the task');
      await tester.tap(find.byTooltip('Close note'));
      await tester.pumpAndSettle();

      final updatedNote = await noteRepository.getById('note-1');
      expect(updatedNote!.content, 'edited from the task');

      final after = await repository.getById('r1');
      expect(
        after!.updatedAt,
        before!.updatedAt,
        reason: 'a note edit in the preview modal must persist through '
            "the note's own path, never the task's save-on-close flow, so "
            "the TASK's updatedAt must stay untouched",
      );
      expect(
        after.noteIds,
        ['note-1'],
        reason: 'previewing/editing a note must never change which notes '
            'are linked',
      );
    });

    testWidgets(
        'a trashed note still offers only restore — no editable preview '
        'modal opens, before or after declining', (tester) async {
      await noteRepository.save(Note(
        id: 'note-trashed',
        title: 'In the trash',
        content: 'trashed content',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
        deletedAt: DateTime(2026, 1, 3),
      ));
      await appState.refreshNotes();
      await repository.save(
        Task.create(id: 'r1', title: 'Task with a trashed link').copyWith(
          noteIds: const ['note-trashed'],
        ),
      );
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Task with a trashed link'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('in trash'));
      await tester.pumpAndSettle();

      expect(find.text('Note in trash'), findsOneWidget);
      expect(
        find.byKey(const Key('task-note-preview')),
        findsNothing,
        reason: 'a trashed note must not open an editable preview modal '
            'while still in the trash',
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('task-note-preview')),
        findsNothing,
        reason: 'declining the restore must leave no preview modal open',
      );
    });

    testWidgets(
        '"Open in full editor" (secondary action) still navigates to the '
        'note and closes the task dialog — demoted, not deleted',
        (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Meeting notes',
        content: 'agenda',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await appState.refreshNotes();
      await repository.save(
        Task.create(id: 'r1', title: 'Has a note').copyWith(
          noteIds: const ['note-1'],
        ),
      );
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Has a note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meeting notes'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('task-note-preview')), findsOneWidget);

      await tester.tap(find.byTooltip('Open in full editor'));
      await tester.pumpAndSettle();

      expect(appState.currentNote?.id, 'note-1');
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'opening in the full editor closes BOTH the note modal '
            'and the task dialog, same as before the modal existed',
      );
    });
  });

  group(
      'notes section — regression: stale _noteResolutions cache after the '
      'note modal closes (bug report: "cuando cierras ese modal no se '
      'guarda la nota")', () {
    testWidgets(
        'reopening a linked note from the still-open task dialog shows the '
        'freshly typed content — not a stale cached Note (the content WAS '
        'persisted; only the in-memory read was stale)', (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Meeting notes',
        content: 'original',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await appState.refreshNotes();
      await repository.save(
        Task.create(id: 'r1', title: 'Has a note').copyWith(
          noteIds: const ['note-1'],
        ),
      );
      await taskState.initialize();
      final before = await repository.getById('r1');
      await pumpBoard(tester);

      await tester.tap(find.text('Has a note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meeting notes'));
      await tester.pumpAndSettle();

      // Toggle to editing, type new content, close the modal via the
      // header X — the FIRST close, not a reopen.
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      final previewField = find.descendant(
        of: find.byKey(const Key('task-note-preview')),
        matching: find.byType(TextField),
      );
      await tester.enterText(previewField, 'freshly typed content');
      await tester.tap(find.byTooltip('Close note'));
      await tester.pumpAndSettle();

      // Back to just the task dialog — still open, never navigated away.
      expect(find.byType(AlertDialog), findsOneWidget);

      // The REAL reproduction: reopen the SAME note from the still-open
      // task dialog. A test that only checked the repository here would
      // have passed against the broken build — this reopen is what exposes
      // a stale in-memory `_noteResolutions` cache that never refreshed
      // after the modal closed.
      await tester.tap(find.text('Meeting notes'));
      await tester.pumpAndSettle();

      final rendered = tester.widget<NoteXMarkdownView>(
        find.descendant(
          of: find.byKey(const Key('task-note-preview')),
          matching: find.byType(NoteXMarkdownView),
        ),
      );
      expect(
        rendered.data,
        'freshly typed content',
        reason: 'reopening from the still-open task dialog must show the '
            'just-typed content, not the pre-edit Note cached before the '
            'first close',
      );

      final after = await repository.getById('r1');
      expect(
        after!.updatedAt,
        before!.updatedAt,
        reason: 'the edit-close-reopen round trip must never touch the '
            "TASK's own updatedAt",
      );
    });

    testWidgets(
        "editing a note's title inside the note modal persists it via "
        'UpdateNoteUseCase and the NOTES list row reflects the new title '
        'immediately, without marking the task dirty (bug report: "no te '
        'deja cambiar el título de la nota")', (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'August 13, 2026',
        content: 'original',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await appState.refreshNotes();
      await repository.save(
        Task.create(id: 'r1', title: 'Has a note').copyWith(
          noteIds: const ['note-1'],
        ),
      );
      await taskState.initialize();
      final before = await repository.getById('r1');
      await pumpBoard(tester);

      await tester.tap(find.text('Has a note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('August 13, 2026'));
      await tester.pumpAndSettle();

      final titleField = find.byKey(const Key('task-note-title-field'));
      expect(titleField, findsOneWidget,
          reason: 'the note title must be an editable field inside the '
              'modal, not static text');
      await tester.enterText(titleField, 'Grocery list');
      await tester.tap(find.byTooltip('Close note'));
      await tester.pumpAndSettle();

      final persisted = await noteRepository.getById('note-1');
      expect(
        persisted!.title,
        'Grocery list',
        reason: 'the new title must persist through UpdateNoteUseCase',
      );
      expect(
        persisted.content,
        'original',
        reason: 'editing the title must never touch the content',
      );

      expect(
        find.text('Grocery list'),
        findsOneWidget,
        reason: 'the NOTES list row must reflect the new title once the '
            'modal closes — without this, two notes created the same day '
            'are indistinguishable in the list',
      );
      expect(find.text('August 13, 2026'), findsNothing);

      final after = await repository.getById('r1');
      expect(
        after!.updatedAt,
        before!.updatedAt,
        reason: "editing a linked note's title must never mark the TASK "
            'dirty or touch its updatedAt',
      );
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
        'no Save/Cancel footer renders — save-on-close replaced it, and '
        'the timer control still sits with the task', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Separate me'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Separate me'));
      await tester.pumpAndSettle();

      // The old actions row (Cancel/Save) is gone entirely — removed along
      // with the buttons themselves (save-on-close replaces them; see the
      // dedicated 'save on close' group below), reclaiming the vertical
      // space AlertDialog reserved for it.
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(
        dialog.actions,
        isNull,
        reason: 'the footer was removed along with Save/Cancel, not just '
            'the timer control lifted out of it',
      );
      expect(find.text('Save'), findsNothing);
      expect(find.text('Cancel'), findsNothing);

      // The timer control still renders inside the task section, grouped
      // with the task rather than any footer.
      expect(find.text('Start timer'), findsOneWidget);
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

  group('task detail dialog — two-column issue layout', () {
    testWidgets(
        'renders the left content column (title/description/notes) beside '
        'a right sidebar (status/details/timestamps) on a wide window',
        (tester) async {
      await noteRepository.save(Note(
        id: 'note-1',
        title: 'Spec doc',
        content: '',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await appState.refreshNotes();
      await repository.save(
        Task.create(id: 'r1', title: 'Two column task').copyWith(
          noteIds: const ['note-1'],
        ),
      );
      await taskState.initialize();
      await pumpBoard(tester); // 1400x1200 physical size — a wide window.

      await tester.tap(find.text('Two column task'));
      await tester.pumpAndSettle();

      // Left column content — title and description only. Linked notes no
      // longer render here; they moved to the right sidebar (see below).
      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
      expect(find.text('DESCRIPTION'), findsOneWidget);

      // Right sidebar content — the status control, the Details card's
      // label/value rows, the linked-notes section, and the timestamps.
      expect(
        find.text('To Do'),
        findsOneWidget,
        reason: 'the status control must show the task\'s current status',
      );
      expect(find.text('DETAILS'), findsOneWidget);
      expect(find.text('Project'), findsOneWidget);
      expect(find.text('Scheduled date'), findsOneWidget);
      // Scoped to the dialog itself — the board card behind it (for this
      // same backlog task) also renders its own "Backlog" chip.
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Backlog'),
        ),
        findsOneWidget,
        reason: 'the Details panel must show "Backlog" for a task with no '
            'scheduledDate',
      );
      expect(find.text('Time tracked'), findsOneWidget);
      // No redundant "Notes" count row in the Details panel anymore — the
      // count lives solely in the "NOTES · N" section header below it.
      expect(find.text('Notes'), findsNothing);
      expect(find.text('NOTES · 1'), findsOneWidget);
      expect(find.textContaining('Created'), findsOneWidget);
      expect(find.textContaining('Updated'), findsOneWidget);

      // Geometrically side-by-side, not stacked: the title field (left
      // column) sits to the left of the status control (sidebar).
      final titleX = tester.getTopLeft(find.widgetWithText(TextField, 'Title')).dx;
      final statusX = tester.getTopLeft(find.text('To Do')).dx;
      expect(
        titleX,
        lessThan(statusX),
        reason: 'on a wide window the sidebar must render beside the '
            'content column, not below it',
      );

      // The notes section itself must render inside the sidebar column,
      // not the left content column — the move this test guards.
      final notesX = tester.getTopLeft(find.text('NOTES · 1')).dx;
      expect(
        notesX,
        greaterThan(titleX),
        reason: 'the linked-notes section must render in the right '
            'sidebar, not the left content column',
      );
    });

    testWidgets(
        'stacks the sidebar below the content column below a width '
        'threshold, without a RenderFlex overflow', (tester) async {
      // A narrow desktop window — narrower than the dialog's comfortable
      // two-column width. The dialog itself (not TaskBoard) must adapt: a
      // fixed-width layout here would be the actual overflow bug the brief
      // calls out.
      tester.view.physicalSize = const Size(760, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await repository.save(Task.create(id: 'r1', title: 'Narrow window task'));
      await taskState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: Listenable.merge([taskState, timerState]),
              builder: (context, _) => TaskBoard(
                taskState: taskState,
                themeState: themeState,
                timerState: timerState,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Narrow window task'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'a narrow, resizable desktop window must not overflow — it '
            'must stack instead of squeezing two columns',
      );

      // Stacked: the sidebar's status control renders below the content
      // column's title field, not beside it.
      final titleBottom =
          tester.getBottomLeft(find.widgetWithText(TextField, 'Title')).dy;
      final statusTop = tester.getTopLeft(find.text('To Do')).dy;
      expect(
        statusTop,
        greaterThanOrEqualTo(titleBottom),
        reason: 'below the width threshold, the sidebar must stack under '
            'the content column',
      );
    });

    testWidgets(
        'changing status from the sidebar dropdown goes through '
        'TransitionTaskStatusUseCase, never a direct status write',
        (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Change my status'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Change my status'));
      await tester.pumpAndSettle();

      expect(find.text('To Do'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<TaskStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doing').last);
      await tester.pumpAndSettle();

      expect(
        transitionSpy.calls,
        [('r1', TaskStatus.doing)],
        reason: 'a status change from the dialog sidebar must flow through '
            'the sole transition use case, exactly like the drag gesture '
            'does',
      );
      final persisted = await repository.getById('r1');
      expect(persisted!.status, TaskStatus.doing);

      // The control itself reflects the new status.
      expect(find.text('Doing'), findsOneWidget);
      expect(find.text('To Do'), findsNothing);

      // Triangulation: a second, DIFFERENT transition from the control
      // (not just the one hardcoded path above) must also flow through
      // the same use case, AND the Details panel must reactively show the
      // Blocked reason row now that the local status is blocked — the
      // display-scoping rule (design D3) applies to a dialog-driven
      // transition exactly as it already does to a drag-driven one.
      await tester.tap(find.byType(DropdownButton<TaskStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blocked').last);
      await tester.pumpAndSettle();

      expect(
        transitionSpy.calls,
        [('r1', TaskStatus.doing), ('r1', TaskStatus.blocked)],
        reason: 'every distinct status change must go through the use '
            'case, not just the first one',
      );
      final rePersisted = await repository.getById('r1');
      expect(rePersisted!.status, TaskStatus.blocked);
      expect(
        find.widgetWithText(TextField, 'Blocked reason'),
        findsOneWidget,
        reason: 'the Blocked reason row must appear once status becomes '
            'blocked from the dialog, not only from a drag',
      );
    });
  });

  group('status/project dropdowns release focus after a selection — '
      'diagnosed problem #1', () {
    testWidgets(
        'choosing a status releases focus so no rectangle lingers on the '
        'control', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Focus check'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Focus check'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<TaskStatus>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doing').last);
      await tester.pumpAndSettle();

      // Some node always holds ambient focus in a live app (the dialog's
      // own modal scope, here) — the meaningful assertion is that it is
      // NOT this specific control's own focus node (identified by its
      // debugLabel) any more, since that is the node whose decoration
      // paints the lingering rectangle.
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('task-status'),
        reason: 'the status dropdown must release focus after a selection, '
            'or it keeps painting a focus rectangle around itself',
      );
    });

    testWidgets(
        'choosing a project releases focus so no rectangle lingers on the '
        'control', (tester) async {
      await projectRepository.save(Project(
        id: 'proj-1',
        name: 'Client work',
        colorValue: 0xFF00FF00,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repository.save(Task.create(id: 'r1', title: 'Focus check 2'));
      await taskState.initialize();
      await timerState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Focus check 2'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Client work').last);
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('task-project'),
        reason: 'the project dropdown must release focus after a '
            'selection, or it keeps painting a focus rectangle around '
            'itself',
      );
    });
  });

  group('creating a project from the task detail dialog\'s project '
      'selector', () {
    testWidgets(
        'picking "New project…", naming it and confirming creates it '
        'through CreateProjectUseCase and assigns it to the task '
        'immediately', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Needs a project'));
      await taskState.initialize();
      await timerState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Needs a project'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New project…').last);
      await tester.pumpAndSettle();

      expect(find.text('New Project'), findsOneWidget,
          reason: 'the inline project-creation dialog must open');

      await tester.enterText(
        find.widgetWithText(TextField, 'Project name'),
        'Freelance client',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Went through CreateProjectUseCase / TimerState.createProject — a
      // real project now exists, not a direct write.
      expect(
        timerState.projects.any((p) => p.name == 'Freelance client'),
        isTrue,
        reason: 'the project must have been created via TimerState',
      );

      final createdProject =
          timerState.projects.firstWhere((p) => p.name == 'Freelance client');
      final persisted = await repository.getById('r1');
      expect(
        persisted!.projectId,
        createdProject.id,
        reason: 'the newly created project must be assigned to the task '
            'immediately',
      );
      expect(
        find.text('Freelance client'),
        findsWidgets,
        reason: 'the selector must now show the newly created project',
      );
    });

    testWidgets(
        'an empty or whitespace-only name does nothing — no project is '
        'created, the dialog stays open', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Blank name task'));
      await taskState.initialize();
      await timerState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Blank name task'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New project…').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Project name'),
        '   ',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
        find.text('New Project'),
        findsOneWidget,
        reason: 'a blank name must not close the dialog or create a '
            'project',
      );
      expect(timerState.projects, isEmpty);

      final persisted = await repository.getById('r1');
      expect(persisted!.projectId, isNull);
    });

    testWidgets('cancelling the creation dialog does nothing', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Cancel me'));
      await taskState.initialize();
      await timerState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Cancel me'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New project…').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Project name'),
        'Never created',
      );
      // Both dialogs (the task detail dialog behind, this "New Project"
      // dialog in front) render their own "Cancel" button — scope to the
      // one inside the "New Project" dialog specifically.
      final newProjectDialog = find.ancestor(
        of: find.text('New Project'),
        matching: find.byType(AlertDialog),
      );
      await tester.tap(find.descendant(
        of: newProjectDialog,
        matching: find.text('Cancel'),
      ));
      await tester.pumpAndSettle();

      expect(timerState.projects, isEmpty);
      final persisted = await repository.getById('r1');
      expect(persisted!.projectId, isNull);
    });
  });

  group('scheduled date is editable from the details panel', () {
    testWidgets(
        'picking a date from the calendar reschedules a backlog task, '
        'normalized to local noon, without touching status', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Reschedule me'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Reschedule me'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Backlog'),
        ),
        findsOneWidget,
        reason: 'starts out in the backlog (no scheduledDate)',
      );

      await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Backlog'),
      ));
      await tester.pumpAndSettle();

      // Switch the date picker to text-input entry mode to avoid ambiguous
      // calendar-grid day taps (adjacent months can render the same day
      // number), then type an unambiguous date directly. Scoped to the
      // DatePickerDialog itself — the task dialog behind it has its own
      // TextFields (Title, etc.) still in the tree.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        ),
        '08/20/2026',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final persisted = await repository.getById('r1');
      expect(persisted!.scheduledDate, isNotNull);
      expect(
        persisted.scheduledDate,
        DateTime(2026, 8, 20, 12, 0, 0),
        reason: 'an edited date must be normalized to LOCAL NOON, exactly '
            'like Task.create, or the day component can shift through '
            'Drift\'s timezone conversion',
      );
      expect(
        persisted.status,
        TaskStatus.todo,
        reason: 'a schedule change must never touch status (design D3), '
            'and must never emit the D10 status quartet',
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Aug 20, 2026'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'clearing the date on a scheduled task sends it back to the '
        'backlog', (tester) async {
      await repository.save(Task.create(
        id: 'r1',
        title: 'Clear my date',
        scheduledDate: DateTime(2026, 5, 1),
      ));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Clear my date'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('May 1, 2026'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Clear date (move to backlog)'));
      await tester.pumpAndSettle();

      final persisted = await repository.getById('r1');
      expect(persisted!.scheduledDate, isNull);
      expect(
        persisted.status,
        TaskStatus.todo,
        reason: 'clearing the date must never touch status',
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Backlog'),
        ),
        findsOneWidget,
        reason: 'the control must reflect the backlog immediately',
      );
    });
  });

  group('task detail dialog — save on close (no explicit Save/Cancel)', () {
    testWidgets('closing via the header X persists a changed title',
        (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Old title'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Old title'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'New title via X',
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      final persisted = await repository.getById('r1');
      expect(persisted!.title, 'New title via X');
    });

    testWidgets('closing via Escape persists a changed title',
        (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Old title'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Old title'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'New title via Escape',
      );
      // The framework's default WidgetsApp shortcut maps Escape ->
      // DismissIntent, which the modal route's own action handler resolves
      // via Navigator.maybePop — the exact same path the barrier below
      // uses, and the one PopScope's `canPop: false` in _TaskDetailDialog
      // intercepts to persist first.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final persisted = await repository.getById('r1');
      expect(persisted!.title, 'New title via Escape');
    });

    testWidgets('closing via the barrier persists a changed title',
        (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Old title'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Old title'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'New title via barrier',
      );
      // The dialog is centered and capped well under the 1400x1200 test
      // surface (see pumpBoard's own doc) — this corner is guaranteed to
      // be outside the dialog's own content and land on the ModalBarrier.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      final persisted = await repository.getById('r1');
      expect(persisted!.title, 'New title via barrier');
    });

    testWidgets(
        'opening and closing without editing anything writes nothing '
        '(updatedAt unchanged)', (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Untouched'));
      final before = await repository.getById('r1');
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Untouched'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      final after = await repository.getById('r1');
      expect(
        after!.updatedAt,
        before!.updatedAt,
        reason: 'opening a task to merely look at it must never write — '
            'none of the fields this dialog defers to close time (title, '
            'description, blockedReason) were touched, so updateTask must '
            'never have been called',
      );
    });

    testWidgets(
        'a save failure surfaces via SnackBar rather than disappearing',
        (tester) async {
      await repository.save(Task.create(id: 'r1', title: 'Will fail'));
      final failingTaskState = TaskState(
        createReminder: CreateTaskUseCase(repository),
        getReminders: GetTasksUseCase(repository),
        completeReminder: transitionSpy,
        updateReminder: _ThrowingUpdateTaskUseCase(repository),
        deleteReminder: DeleteTaskUseCase(repository, _NoopSyncEngine()),
        linkNote: LinkNoteToTaskUseCase(repository),
        unlinkNote: UnlinkNoteFromTaskUseCase(repository),
      );
      await failingTaskState.initialize();
      await pumpBoard(tester, overrideTaskState: failingTaskState);

      await tester.tap(find.text('Will fail'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Changed but will fail',
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not save changes'),
        findsOneWidget,
        reason: 'a save failure must surface — there is no Cancel button '
            'to fall back on, so silence would mean the edit vanished '
            'without a trace',
      );
    });
  });

  group(
      'nested dialogs resolve their background from the theme, not a '
      'literal (extends the task detail dialog theme fix to its children)',
      () {
    testWidgets(
        '_CreateProjectDialog resolves its background from '
        "ThemeState.editorBgColor, and its Create button's foreground "
        'contrasts with the literal accent colour', (tester) async {
      themeState.toggleDarkMode();
      await repository.save(Task.create(id: 'r1', title: 'Needs a project'));
      await taskState.initialize();
      await timerState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Needs a project'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New project…').last);
      await tester.pumpAndSettle();

      final newProjectDialogFinder = find.ancestor(
        of: find.text('New Project'),
        matching: find.byType(AlertDialog),
      );
      final newProjectDialog = tester.widget<AlertDialog>(
        newProjectDialogFinder,
      );
      final expectedSurface = Color.alphaBlend(
        themeState.editorBgColor.withValues(alpha: 0.96),
        Colors.black,
      );
      expect(
        newProjectDialog.backgroundColor,
        expectedSurface,
        reason: "_CreateProjectDialog's background must be derived from "
            'ThemeState.editorBgColor, not the ambient seed-tinted '
            'ColorScheme default',
      );

      final createButton = tester.widget<FilledButton>(
        find.descendant(
          of: newProjectDialogFinder,
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
      expect(
        createButton.style?.backgroundColor?.resolve(<WidgetState>{}),
        themeState.accentColor,
      );
    });

    testWidgets(
        '_NotePickerDialog resolves its background from '
        'ThemeState.editorBgColor', (tester) async {
      themeState.toggleDarkMode();
      await repository.save(Task.create(id: 'r1', title: 'Needs a note'));
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Needs a note'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Link note'));
      await tester.pumpAndSettle();

      final pickerDialog = tester.widget<AlertDialog>(
        find.ancestor(
          of: find.text('Link a note'),
          matching: find.byType(AlertDialog),
        ),
      );
      final expectedSurface = Color.alphaBlend(
        themeState.editorBgColor.withValues(alpha: 0.96),
        Colors.black,
      );
      expect(
        pickerDialog.backgroundColor,
        expectedSurface,
        reason: "_NotePickerDialog's background must be derived from "
            'ThemeState.editorBgColor, not the ambient seed-tinted '
            'ColorScheme default',
      );
    });

    testWidgets(
        'the "Note not found" confirmation resolves its background from '
        "ThemeState.editorBgColor, and its Unlink button's foreground "
        'contrasts with the literal accent colour', (tester) async {
      themeState.toggleDarkMode();
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

      // "Note not found" is only the linked-notes row's own label so far
      // (design D9's missing-status affordance) — tapping it is what
      // actually opens the confirmation dialog under test.
      expect(find.text('Note not found'), findsOneWidget);
      await tester.tap(find.text('Note not found'));
      await tester.pumpAndSettle();

      // Distinguished from the row's own "Note not found" label (still
      // present behind this dialog) by its own unique content text.
      final confirmDialogFinder = find.ancestor(
        of: find.text('This linked note no longer exists.'),
        matching: find.byType(AlertDialog),
      );
      final confirmDialog = tester.widget<AlertDialog>(confirmDialogFinder);
      final expectedSurface = Color.alphaBlend(
        themeState.editorBgColor.withValues(alpha: 0.96),
        Colors.black,
      );
      expect(confirmDialog.backgroundColor, expectedSurface);

      final unlinkButton = tester.widget<FilledButton>(
        find.descendant(
          of: confirmDialogFinder,
          matching: find.widgetWithText(FilledButton, 'Unlink'),
        ),
      );
      final expectedForeground =
          themeState.accentColor.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white;
      expect(
        unlinkButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        expectedForeground,
      );
    });

    testWidgets(
        'the "Note in trash" confirmation resolves its background from '
        'ThemeState.editorBgColor', (tester) async {
      themeState.toggleDarkMode();
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
          noteIds: const ['note-trashed'],
        ),
      );
      await taskState.initialize();
      await pumpBoard(tester);

      await tester.tap(find.text('Task with a trashed link'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('in trash'));
      await tester.pumpAndSettle();

      expect(find.text('Note in trash'), findsOneWidget);

      final confirmDialog = tester.widget<AlertDialog>(
        find.ancestor(
          of: find.text('Note in trash'),
          matching: find.byType(AlertDialog),
        ),
      );
      final expectedSurface = Color.alphaBlend(
        themeState.editorBgColor.withValues(alpha: 0.96),
        Colors.black,
      );
      expect(confirmDialog.backgroundColor, expectedSurface);
    });
  });

  group('board project filter (item 2) — narrows every column, backlog '
      'tasks included', () {
    /// Seeds two projects and one task per project in each of Todo,
    /// Blocked and (backlog) Done, plus one project-less backlog Todo task
    /// — enough to prove the filter reaches every column and never leaks a
    /// non-matching project's task into any bucket.
    Future<void> seedMixedProjectTasks() async {
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
        Task.create(id: 'todo-a', title: 'Todo A').copyWith(
          projectId: 'proj-a',
        ),
      );
      await repository.save(
        Task.create(id: 'todo-b', title: 'Todo B').copyWith(
          projectId: 'proj-b',
        ),
      );
      await repository.save(
        Task.create(id: 'blocked-a', title: 'Blocked A').copyWith(
          projectId: 'proj-a',
          status: TaskStatus.blocked,
        ),
      );
      await repository.save(
        Task.create(id: 'blocked-b', title: 'Blocked B').copyWith(
          projectId: 'proj-b',
          status: TaskStatus.blocked,
        ),
      );
      // Done, backlog (no scheduledDate) — the bucket the brief singles
      // out as easy to leak from.
      await repository.save(
        Task.create(id: 'done-a', title: 'Done Backlog A').copyWith(
          projectId: 'proj-a',
          status: TaskStatus.done,
        ),
      );
      await repository.save(
        Task.create(id: 'done-b', title: 'Done Backlog B').copyWith(
          projectId: 'proj-b',
          status: TaskStatus.done,
        ),
      );
      // No project at all — must appear only under the "No Project" filter.
      await repository.save(
        Task.create(id: 'todo-none', title: 'Todo No Project'),
      );

      await taskState.initialize();
    }

    testWidgets('defaults to All projects — every task renders unfiltered',
        (tester) async {
      expect(themeState.taskBoardProjectFilter, TaskBoard.projectFilterAll);

      await seedMixedProjectTasks();
      await pumpBoard(tester);

      for (final title in [
        'Todo A',
        'Todo B',
        'Blocked A',
        'Blocked B',
        'Done Backlog A',
        'Done Backlog B',
        'Todo No Project',
      ]) {
        expect(find.text(title), findsOneWidget, reason: '$title must be '
            'visible with the default All-projects filter');
      }
    });

    testWidgets(
        'filtering to one project hides every other project\'s tasks in '
        'every column, including the Done backlog bucket', (tester) async {
      await seedMixedProjectTasks();
      themeState.setTaskBoardProjectFilter('proj-a');
      await pumpBoard(tester);

      expect(find.text('Todo A'), findsOneWidget);
      expect(find.text('Blocked A'), findsOneWidget);
      expect(find.text('Done Backlog A'), findsOneWidget);

      expect(find.text('Todo B'), findsNothing);
      expect(find.text('Blocked B'), findsNothing);
      expect(find.text('Done Backlog B'), findsNothing);
      expect(
        find.text('Todo No Project'),
        findsNothing,
        reason: 'a project filter must also exclude project-less tasks',
      );
    });

    testWidgets(
        '"No Project" filters to only tasks with a null projectId',
        (tester) async {
      await seedMixedProjectTasks();
      themeState.setTaskBoardProjectFilter(TaskBoard.projectFilterNone);
      await pumpBoard(tester);

      expect(find.text('Todo No Project'), findsOneWidget);

      expect(find.text('Todo A'), findsNothing);
      expect(find.text('Todo B'), findsNothing);
      expect(find.text('Blocked A'), findsNothing);
      expect(find.text('Blocked B'), findsNothing);
      expect(find.text('Done Backlog A'), findsNothing);
      expect(find.text('Done Backlog B'), findsNothing);
    });
  });
}
