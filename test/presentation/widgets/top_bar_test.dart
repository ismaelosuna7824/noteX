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
import 'package:notex/application/use_cases/update_note_use_case.dart';
import 'package:notex/domain/repositories/auth_repository.dart';
import 'package:notex/domain/services/connectivity_service.dart';
import 'package:notex/domain/services/sync_service.dart';
import 'package:notex/domain/services/update_service.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_note_project_repository.dart';
import 'package:notex/infrastructure/local/drift_note_repository.dart';
import 'package:notex/presentation/state/app_state.dart';
import 'package:notex/presentation/state/security_state.dart';
import 'package:notex/presentation/state/theme_state.dart';
import 'package:notex/presentation/state/tiling_state.dart';
import 'package:notex/presentation/widgets/top_bar.dart';

/// Minimal throwing fakes — same `_UnusedX` pattern as `app_state_test.dart`.
class _UnusedUpdateService implements UpdateService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

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

class _FakeAuthRepositoryWithStream implements AuthRepository {
  @override
  Stream<bool> get authStateChanges => const Stream<bool>.empty();

  // TopBar's own build() reads AppState.isAuthenticated (avatar/greeting).
  @override
  bool get isAuthenticated => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

/// Covers [TopBarState.requestSearchFocus] — the Cmd/Ctrl+K app-wide
/// shortcut's entry point into the search field (see `AppShell`/
/// `AppShortcuts`), reached through a [GlobalKey] since the search
/// [FocusNode] itself is private to [TopBarState].
void main() {
  late AppDatabase db;
  late AppState appState;
  late ThemeState themeState;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    GetIt.instance.registerSingleton<SecurityState>(SecurityState());
    GetIt.instance.registerSingleton<TilingState>(TilingState());
    themeState = ThemeState();

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
    await db.close();
  });

  testWidgets('requestSearchFocus focuses the search field', (tester) async {
    final topBarKey = GlobalKey<TopBarState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopBar(
            key: topBarKey,
            appState: appState,
            themeState: themeState,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);

    topBarKey.currentState!.requestSearchFocus();
    await tester.pump();

    expect(field.focusNode!.hasFocus, isTrue);
  });
}
