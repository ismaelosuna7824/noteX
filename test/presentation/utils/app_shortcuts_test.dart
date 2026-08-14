import 'dart:async';

import 'package:drift/native.dart';
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
import 'package:notex/presentation/state/tiling_state.dart';
import 'package:notex/presentation/utils/app_shortcuts.dart';
import 'package:notex/presentation/widgets/sidebar.dart';

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

/// [AppState]'s constructor subscribes to `authStateChanges` immediately.
class _FakeAuthRepositoryWithStream implements AuthRepository {
  @override
  Stream<bool> get authStateChanges => const Stream<bool>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in this test: ${invocation.memberName}');
}

/// Covers the app-wide keyboard shortcut layer: sidebar navigation
/// (Ctrl/Cmd+1..8, derived from the same list `Sidebar` renders from — the
/// hidden-Markdown hazard), new note/task, search, and the shortcuts help
/// sheet trigger. Exercised against a real [AppState] (in-memory Drift DB,
/// same fixture as `app_state_test.dart`) so navigation assertions are
/// against actual `selectedPageIndex`, not a mocked call.
void main() {
  late AppDatabase db;
  late AppState appState;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    GetIt.instance.registerSingleton<SecurityState>(SecurityState());
    GetIt.instance.registerSingleton<TilingState>(TilingState());

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

  Future<void> pumpShortcuts(
    WidgetTester tester, {
    VoidCallback? onNewNote,
    void Function(BuildContext context)? onNewTask,
    VoidCallback? onSearch,
    void Function(BuildContext context)? onShowHelp,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppShortcuts(
            appState: appState,
            onNewNote: onNewNote ?? () {},
            onNewTask: onNewTask ?? (_) {},
            onSearch: onSearch ?? () {},
            onShowHelp: onShowHelp ?? (_) {},
            // Same shape as AppShell's own wiring: a real autofocus Focus
            // node below AppShortcuts so a key event always has somewhere
            // to start bubbling from, without tapping anything first.
            child: const Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      ),
    );
  }

  const digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
  ];

  group('numeric section shortcuts', () {
    testWidgets(
        'each numeric shortcut opens the section the sidebar shows in that '
        'position', (tester) async {
      await pumpShortcuts(tester);
      await tester.pump();

      // Sidebar.visiblePageIndices/visibleSectionLabels are the exact list
      // Sidebar itself renders from — asserting against them (not a
      // hand-copied literal) is what actually proves the shortcut derives
      // its mapping from the sidebar instead of a raw page index.
      final indices = Sidebar.visiblePageIndices;
      final labels = Sidebar.visibleSectionLabels;
      expect(indices.length, greaterThanOrEqualTo(kNumberedSectionShortcutCount));

      for (var i = 0; i < kNumberedSectionShortcutCount; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(digitKeys[i]);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pumpAndSettle();

        expect(
          appState.selectedPageIndex,
          indices[i],
          reason: 'Ctrl+${i + 1} should open "${labels[i]}"',
        );
      }
    });

    testWidgets(
        'Ctrl+5 opens the 5th visible section (Timer), never the hidden '
        'Markdown page (raw index 5)', (tester) async {
      // THE HAZARD: Markdown's own page index is 5. If the numeric
      // shortcuts ever mapped position -> raw page index instead of
      // Sidebar.visiblePageIndices, Ctrl+5 could land on page 5 (hidden,
      // silently redirected to Home by AppState.navigateToPage) instead of
      // the 5th visible item, which is Timer (page index 4).
      await pumpShortcuts(tester);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(appState.selectedPageIndex, isNot(5));
      expect(appState.selectedPageIndex, Sidebar.visiblePageIndices[4]);
      expect(Sidebar.visibleSectionLabels[4], 'Timer');
    });
  });

  testWidgets('Ctrl+N fires the new-note action', (tester) async {
    var called = false;
    await pumpShortcuts(tester, onNewNote: () => called = true);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    expect(called, isTrue);
  });

  testWidgets('Ctrl+Shift+N fires the new-task action', (tester) async {
    var called = false;
    await pumpShortcuts(tester, onNewTask: (_) => called = true);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    expect(called, isTrue);
  });

  testWidgets('Ctrl+K fires the search action', (tester) async {
    var called = false;
    await pumpShortcuts(tester, onSearch: () => called = true);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    expect(called, isTrue);
  });

  testWidgets('Ctrl+/ fires the show-help action', (tester) async {
    var called = false;
    await pumpShortcuts(tester, onShowHelp: (_) => called = true);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    expect(called, isTrue);
  });

  testWidgets('F11 toggles zen mode; Escape only exits it while active',
      (tester) async {
    // AppState.enterZenMode() is a no-op without a current note (zen mode is
    // the editor's own focus mode) — open one first so F11 has something to
    // toggle, matching real usage.
    await appState.createNewNote();
    await pumpShortcuts(tester);
    await tester.pump();
    expect(appState.isZenMode, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    expect(appState.isZenMode, isTrue);

    // Escape while zen mode is active exits it.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(appState.isZenMode, isFalse);

    // Escape while zen mode is NOT active must not throw and must leave
    // isZenMode untouched — this is what lets Escape still fall through to
    // e.g. a dialog's own dismiss-on-Escape when zen mode is off.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(appState.isZenMode, isFalse);
  });

  group('focus-tree placement — the real app bug this file guards against',
      () {
    // These reproduce the actual production bug: `AppShortcuts` used to be
    // mounted inside `AppShell` (a descendant of `MaterialApp`'s `home`
    // route), not above `MaterialApp`'s `Navigator`. `Shortcuts` dispatches
    // by walking UP the ancestor chain from whatever is currently focused —
    // it never looks at sibling subtrees. A dialog pushed via
    // `showDialog`/`showAnimatedDialog` becomes a SIBLING route in the same
    // `Navigator`'s `Overlay`, not a descendant of the first route's page
    // content, so a `Shortcuts` layer mounted inside that first route's page
    // (the old `AppShell`-level placement) is structurally unreachable from
    // the dialog's focus chain. `flutter test` never caught this because
    // every existing test above mounts `AppShortcuts` as the outermost
    // widget in `pumpShortcuts` — a shape that happens to already sit above
    // any dialog a test might push, unlike the real app's `AppShell`-nested
    // placement.
    testWidgets(
        'REPRODUCES THE BUG: a Shortcuts layer mounted inside a route (the '
        'old AppShell-level placement) does NOT fire once a dialog (a '
        'sibling route on the same Navigator) is open', (tester) async {
      var called = false;
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            // Same shape as the pre-fix `AppShell.build()`: AppShortcuts is
            // a descendant of the route's own page content, not an
            // ancestor of the Navigator.
            body: AppShortcuts(
              appState: appState,
              onNewNote: () => called = true,
              onNewTask: (_) {},
              onSearch: () {},
              onShowHelp: (_) {},
              child: const Focus(autofocus: true, child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pump();

      // Push a second route on the SAME Navigator — exactly what every
      // dialog in this app does (New Task, shortcuts help, note modals,
      // task detail, etc).
      unawaited(
        navigatorKey.currentState!.push(
          DialogRoute<void>(
            context: navigatorKey.currentContext!,
            builder: (_) => const AlertDialog(title: Text('A dialog')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(called, isFalse);
    });

    testWidgets(
        'THE FIX: a Shortcuts layer mounted above the Navigator (via '
        "MaterialApp's builder, wrapping the routed child) DOES fire while "
        'a dialog (a sibling route) is open', (tester) async {
      var called = false;
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => AppShortcuts(
            appState: appState,
            onNewNote: () => called = true,
            onNewTask: (_) {},
            onSearch: () {},
            onShowHelp: (_) {},
            child: child!,
          ),
          home: const Scaffold(
            body: Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pump();

      unawaited(
        navigatorKey.currentState!.push(
          DialogRoute<void>(
            context: navigatorKey.currentContext!,
            builder: (_) => const AlertDialog(title: Text('A dialog')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(called, isTrue);
    });

    testWidgets(
        'a shortcut fires when nothing was explicitly focused by the test — '
        "only AppShell's own default autofocus node claimed focus, mounted "
        'above the Navigator like the real app', (tester) async {
      var called = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppShortcuts(
            appState: appState,
            onNewNote: () => called = true,
            onNewTask: (_) {},
            onSearch: () {},
            onShowHelp: (_) {},
            child: child!,
          ),
          home: const Scaffold(
            body: Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      );
      // No tester.tap(...) anywhere — relies purely on the autofocus node.
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(called, isTrue);
    });

    testWidgets(
        'Escape still dismisses a dialog when AppShortcuts wraps the '
        'Navigator and zen mode is off (ExitZenModeIntent is disabled, so '
        "the raw key falls through to MaterialApp's own default "
        'Escape-dismiss handling)', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => AppShortcuts(
            appState: appState,
            onNewNote: () {},
            onNewTask: (_) {},
            onSearch: () {},
            onShowHelp: (_) {},
            child: child!,
          ),
          home: const Scaffold(
            body: Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pump();
      expect(appState.isZenMode, isFalse);

      unawaited(
        navigatorKey.currentState!.push(
          DialogRoute<void>(
            context: navigatorKey.currentContext!,
            builder: (_) => const AlertDialog(title: Text('A dialog')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A dialog'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('A dialog'), findsNothing);
    });
  });

  group('typing into a focused text field', () {
    testWidgets(
        'plain digits/letters without a modifier do not fire any shortcut '
        'action — the keystroke is inserted into the field instead',
        (tester) async {
      var newNoteCalled = false;
      var searchCalled = false;
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppShortcuts(
              appState: appState,
              onNewNote: () => newNoteCalled = true,
              onNewTask: (_) {},
              onSearch: () => searchCalled = true,
              onShowHelp: (_) {},
              child: TextField(controller: controller, autofocus: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Type the bare keys our shortcuts use a modifier for — no
      // Cmd/Ctrl held down.
      await tester.enterText(find.byType(TextField), '1nk');
      await tester.pump();

      expect(controller.text, '1nk');
      expect(newNoteCalled, isFalse);
      expect(searchCalled, isFalse);
      expect(appState.selectedPageIndex, 0);
    });
  });
}
