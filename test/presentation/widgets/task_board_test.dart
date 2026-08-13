import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/services/sync_engine.dart';
import 'package:notex/application/use_cases/task/create_task_use_case.dart';
import 'package:notex/application/use_cases/task/delete_task_use_case.dart';
import 'package:notex/application/use_cases/task/get_tasks_use_case.dart';
import 'package:notex/application/use_cases/task/transition_task_status_use_case.dart';
import 'package:notex/application/use_cases/task/update_task_use_case.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/repositories/auth_repository.dart';
import 'package:notex/domain/services/connectivity_service.dart';
import 'package:notex/domain/services/sync_service.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_task_repository.dart';
import 'package:notex/presentation/state/task_state.dart';
import 'package:notex/presentation/state/theme_state.dart';
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
    );
    themeState = ThemeState();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpBoard(WidgetTester tester) async {
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
              animation: taskState,
              builder: (context, _) =>
                  TaskBoard(taskState: taskState, themeState: themeState),
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
}
