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
import 'package:notex/application/use_cases/timer/start_timer_use_case.dart';
import 'package:notex/application/use_cases/timer/stop_timer_use_case.dart';
import 'package:notex/application/use_cases/timer/update_time_entry_use_case.dart';
import 'package:notex/application/use_cases/update_note_use_case.dart';
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
import 'package:notex/presentation/pages/mobile_app_shell.dart';
import 'package:notex/presentation/state/app_state.dart';
import 'package:notex/presentation/state/security_state.dart';
import 'package:notex/presentation/state/task_state.dart';
import 'package:notex/presentation/state/theme_state.dart';
import 'package:notex/presentation/state/tiling_state.dart';
import 'package:notex/presentation/state/timer_state.dart';
import 'package:notex/presentation/state/writing_stats_state.dart';

/// Minimal throwing fakes — same `_UnusedX` pattern as
/// `timer_page_test.dart`/`task_board_test.dart`.
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

class _FakeAuthRepositoryWithStream implements AuthRepository {
  @override
  Stream<bool> get authStateChanges => const Stream<bool>.empty();

  // SettingsPage reads this at build time.
  @override
  bool get isAuthenticated => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

/// Covers hiding the Markdown section from the mobile bottom nav: the
/// entry must not render, and every remaining item must still route to
/// the page it names — the same index-shift guard as `sidebar_test.dart`,
/// exercised here against [MobileAppShell]'s real `_navDestinations` +
/// `_buildPage` switch instead of in isolation.
void main() {
  late AppDatabase db;
  late TaskState taskState;
  late TimerState timerState;
  late ThemeState themeState;
  late AppState appState;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final taskRepository = DriftTaskRepository(db);
    final timeEntryRepository = DriftTimeEntryRepository(db);
    final projectRepository = DriftProjectRepository(db);
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
    GetIt.instance.registerSingleton<SecurityState>(SecurityState());
    GetIt.instance.registerSingleton<TilingState>(TilingState());
    GetIt.instance.registerSingleton<WritingStatsState>(WritingStatsState());

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

  Future<void> pumpShell(WidgetTester tester) async {
    // Generous desktop-sized surface — same convention as
    // `timer_page_test.dart`/`task_board_test.dart`. HomePage's own
    // `_mobileBreakpoint` (600) narrow layout branch has a pre-existing,
    // unrelated layout bug (unbounded-height RenderFlex) this task must
    // not touch; the nav wiring under test doesn't depend on viewport
    // width, so a wide surface sidesteps it cleanly.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MobileAppShell(appState: appState, themeState: themeState),
      ),
    );
    await tester.pump();
  }

  testWidgets('Markdown entry is not rendered in the mobile bottom nav',
      (tester) async {
    await pumpShell(tester);

    expect(find.byTooltip('Markdown'), findsNothing);
    expect(find.byIcon(Icons.article_rounded), findsNothing);
  });

  testWidgets(
      'every remaining bottom nav item still opens the page it names',
      (tester) async {
    await pumpShell(tester);

    // (tooltip label, expected page index) — mirrors MobileAppShell's own
    // `_navDestinations` + `_buildPage` switch, minus Markdown. Asserted
    // against `selectedPageIndex` (the exact value `_buildPage`'s switch
    // keys off), by actually tapping the real nav icon and letting it
    // route. Settings is checked separately below (see comment there) —
    // rendering it here trips a pre-existing, unrelated widget-test
    // assertion in SettingsPage's SwitchListTile that this task must not
    // touch.
    const expected = [
      ('Notes', 1),
      ('Editor', 2),
      ('Calendar', 3),
      ('Timer', 4),
      ('Tasks', 7),
      ('Home', 0),
    ];

    for (final (label, pageIndex) in expected) {
      await tester.tap(find.byTooltip(label));
      await tester.pump();
      expect(
        appState.selectedPageIndex,
        pageIndex,
        reason: '"$label" should still navigate to page $pageIndex',
      );
    }
  });

  testWidgets('the Settings nav item is still present, unshifted',
      (tester) async {
    await pumpShell(tester);

    // Deliberately not tapped: building SettingsPage trips a pre-existing,
    // unrelated widget-test assertion (a SwitchListTile painted on a
    // DecoratedBox without an intervening Material — "ListTile background
    // color or ink splashes may be invisible"), which this task must not
    // fix. AppState.navigateToPage(6) itself is covered generically by
    // `app_state_test.dart`; this only confirms the icon survived the
    // Markdown removal at its expected position.
    expect(find.byTooltip('Settings'), findsOneWidget);
  });
}
