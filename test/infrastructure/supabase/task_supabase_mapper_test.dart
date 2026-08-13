import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/infrastructure/supabase/task_supabase_mapper.dart';

/// One test per row of design D2's status-resolution contract table, plus
/// the D10 push-payload contract (R1/R2) and the round-trip asymmetry
/// around `statusPendingPush`.
void main() {
  Task buildTask({
    TaskStatus status = TaskStatus.todo,
    DateTime? statusChangedAt,
    bool statusPendingPush = true,
    DateTime? completedAt,
    String? blockedReason,
    String? externalProvider,
    String? externalId,
    String? externalUrl,
    String? externalCachedTitle,
    DateTime? externalLastSyncedAt,
  }) {
    return Task(
      id: 'r1',
      title: 'Buy milk',
      scheduledDate: DateTime(2026, 3, 4, 12),
      status: status,
      statusChangedAt: statusChangedAt,
      statusPendingPush: statusPendingPush,
      completedAt: completedAt,
      blockedReason: blockedReason,
      description: 'get oat milk',
      noteId: 'note-1',
      externalProvider: externalProvider,
      externalId: externalId,
      externalUrl: externalUrl,
      externalCachedTitle: externalCachedTitle,
      externalLastSyncedAt: externalLastSyncedAt,
      createdAt: DateTime(2026, 1, 1, 8),
      updatedAt: DateTime(2026, 1, 2, 9),
      version: 3,
      syncStatus: SyncStatus.pendingSync,
      userId: 'user-1',
    );
  }

  Map<String, dynamic> rowFor(
    TaskStatus? status,
    bool isCompleted, {
    DateTime? completedAt,
    DateTime? statusChangedAt,
  }) {
    return {
      'id': 'r1',
      'user_id': 'user-1',
      'title': 'Buy milk',
      'scheduled_date': DateTime(2026, 3, 4, 12).toUtc().toIso8601String(),
      'description': 'get oat milk',
      'status': status?.name,
      'is_completed': isCompleted,
      'completed_at': completedAt?.toUtc().toIso8601String(),
      'status_changed_at': statusChangedAt?.toUtc().toIso8601String(),
      'created_at': DateTime(2026, 1, 1, 8).toUtc().toIso8601String(),
      'updated_at': DateTime(2026, 1, 2, 9).toUtc().toIso8601String(),
      'version': 3,
    };
  }

  group('fromMap — M4: status=done is authoritative', () {
    test('is_completed is true for done', () {
      final task = TaskSupabaseMapper.fromMap(
        rowFor(TaskStatus.done, true, completedAt: DateTime(2026, 3, 3)),
      );
      expect(task.status, TaskStatus.done);
      expect(task.isDone, isTrue);
    });

    for (final s in [TaskStatus.todo, TaskStatus.doing, TaskStatus.blocked]) {
      test('is_completed is false for $s', () {
        final task = TaskSupabaseMapper.fromMap(rowFor(s, false));
        expect(task.status, s);
        expect(task.isDone, isFalse);
      });
    }
  });

  group('fromMap — M5: absent/unrecognized status falls back to the legacy '
      'boolean', () {
    test('M5a: absent status + is_completed true -> done', () {
      final task = TaskSupabaseMapper.fromMap(rowFor(null, true));
      expect(task.status, TaskStatus.done);
    });

    test('M5b: unrecognized status + is_completed false -> todo, no throw',
        () {
      final row = rowFor(null, false);
      row['status'] = 'archived';

      final task = TaskSupabaseMapper.fromMap(row);

      expect(task.status, TaskStatus.todo);
    });
  });

  group('fromMap — M8 contradiction gate', () {
    for (final s in [TaskStatus.todo, TaskStatus.doing, TaskStatus.blocked]) {
      group('status=$s, is_completed=true', () {
        test('M8a: statusChangedAt null -> done (backfilled row)', () {
          final task = TaskSupabaseMapper.fromMap(
            rowFor(s, true, completedAt: DateTime(2026, 3, 1)),
          );
          expect(task.status, TaskStatus.done);
        });

        test('M8b: completedAt > statusChangedAt -> done (genuine old-'
            'client completion)', () {
          final task = TaskSupabaseMapper.fromMap(rowFor(
            s,
            true,
            statusChangedAt: DateTime(2026, 3, 1),
            completedAt: DateTime(2026, 3, 2),
          ));
          expect(task.status, TaskStatus.done);
        });

        test('M8b boundary: completedAt == statusChangedAt -> done', () {
          final same = DateTime(2026, 3, 1, 12, 30);
          final task = TaskSupabaseMapper.fromMap(rowFor(
            s,
            true,
            statusChangedAt: same,
            completedAt: same,
          ));
          expect(task.status, TaskStatus.done);
        });

        test('M8c (stranding regression): completedAt < statusChangedAt '
            '-> status preserved', () {
          final task = TaskSupabaseMapper.fromMap(rowFor(
            s,
            true,
            statusChangedAt: DateTime(2026, 3, 2),
            completedAt: DateTime(2026, 3, 1),
          ));
          expect(task.status, s);
        });

        test('M8d (unreachable defense-in-depth): completedAt null -> '
            'status preserved', () {
          final task = TaskSupabaseMapper.fromMap(rowFor(
            s,
            true,
            statusChangedAt: DateTime(2026, 3, 1),
          ));
          expect(task.status, s);
        });
      });
    }

    test('row 5: status=done + is_completed=false -> done (ungated)', () {
      final task = TaskSupabaseMapper.fromMap(rowFor(TaskStatus.done, false));
      expect(task.status, TaskStatus.done);
    });
  });

  group('fromMap — completedAt normalization', () {
    test('M8c: resolution.completedAt is null when status is preserved '
        '(non-done)', () {
      final task = TaskSupabaseMapper.fromMap(rowFor(
        TaskStatus.doing,
        true,
        statusChangedAt: DateTime(2026, 3, 2),
        completedAt: DateTime(2026, 3, 1),
      ));
      expect(task.status, TaskStatus.doing);
      expect(task.completedAt, isNull);
    });

    test('M8d: resolution.completedAt is null when status is preserved '
        '(completedAt was null on input)', () {
      final task = TaskSupabaseMapper.fromMap(rowFor(
        TaskStatus.blocked,
        true,
        statusChangedAt: DateTime(2026, 3, 1),
      ));
      expect(task.status, TaskStatus.blocked);
      expect(task.completedAt, isNull);
    });
  });

  group('toMap — D10 payload contract', () {
    test('includeStatusFields: false omits all four quartet keys', () {
      final data = TaskSupabaseMapper.toMap(
        buildTask(status: TaskStatus.done, statusChangedAt: DateTime.now()),
        includeStatusFields: false,
      );

      expect(data.containsKey('status'), isFalse);
      expect(data.containsKey('is_completed'), isFalse);
      expect(data.containsKey('completed_at'), isFalse);
      expect(data.containsKey('status_changed_at'), isFalse);
    });

    test('includeStatusFields: true with a null statusChangedAt omits only '
        'that key (R2), includes the other three (R1)', () {
      final data = TaskSupabaseMapper.toMap(
        buildTask(status: TaskStatus.doing, statusChangedAt: null),
        includeStatusFields: true,
      );

      expect(data.containsKey('status_changed_at'), isFalse);
      expect(data['status'], 'doing');
      expect(data.containsKey('is_completed'), isTrue);
      expect(data.containsKey('completed_at'), isTrue);
    });

    test('includeStatusFields: true with a non-null statusChangedAt '
        'includes all four quartet keys', () {
      final data = TaskSupabaseMapper.toMap(
        buildTask(
          status: TaskStatus.done,
          statusChangedAt: DateTime(2026, 3, 1),
          completedAt: DateTime(2026, 3, 1),
        ),
        includeStatusFields: true,
      );

      expect(data['status'], 'done');
      expect(data['is_completed'], isTrue);
      expect(data.containsKey('completed_at'), isTrue);
      expect(data.containsKey('status_changed_at'), isTrue);
    });
  });

  group('toMap — un-completing (row 5 precondition, slice 2 task 2.12)', () {
    // The board can now drag a `done` card back to another column. Design's
    // row-5 invariant ("no shipped client authors is_completed=false
    // without also authoring status") holds only because the quartet is
    // emitted as one unit (D10 R1). This proves that holds for the newly
    // reachable un-complete direction, not just the complete direction
    // already covered above.
    test('emits is_completed=false together with the new status — never '
        'is_completed alone', () {
      final unCompleted = buildTask(
        status: TaskStatus.todo,
        statusChangedAt: DateTime(2026, 3, 5),
        completedAt: null,
        statusPendingPush: true,
      );

      final data = TaskSupabaseMapper.toMap(
        unCompleted,
        includeStatusFields: true,
      );

      expect(data['status'], 'todo');
      expect(data['is_completed'], isFalse);
      expect(data.containsKey('status'), isTrue);
      expect(data.containsKey('is_completed'), isTrue);
    });
  });

  group('backlog task — nullable scheduled_date (schema v19)', () {
    test('toMap emits a null scheduled_date for a backlog task', () {
      final backlog = Task(
        id: 'r1',
        title: 'Someday',
        createdAt: DateTime(2026, 1, 1, 8),
        updatedAt: DateTime(2026, 1, 2, 9),
      );

      final data = TaskSupabaseMapper.toMap(
        backlog,
        includeStatusFields: false,
      );

      expect(data.containsKey('scheduled_date'), isTrue);
      expect(data['scheduled_date'], isNull);
    });

    // Named after design D5's "bounded degradation" claim. A remote row
    // with a null scheduled_date is legal once the v19 DDL lands (a
    // backlog task another client created and pushed). This is the root
    // fix: THIS mapper parses it defensively and returns a backlog task
    // rather than throwing — it no longer depends on the sync pull loop's
    // pre-existing per-row try/catch (supabase_sync_adapter.dart:324-329)
    // to survive a backlog row. That try/catch remains the safety net for
    // genuinely older, unmodified clients this repo cannot execute in a
    // test — see design D5's "Accepted, bounded degradation" note.
    test('fromMap parses a null scheduled_date as a backlog task, without '
        'throwing', () {
      final row = rowFor(TaskStatus.todo, false);
      row['scheduled_date'] = null;

      final task = TaskSupabaseMapper.fromMap(row);

      expect(task.scheduledDate, isNull);
    });
  });

  group('round trip', () {
    test('fromMap(toMap(t)) preserves every field except statusPendingPush, '
        'which is always false inbound — including the five external-'
        'reference fields, previously untested with a real (non-null) '
        'value', () {
      final original = buildTask(
        status: TaskStatus.blocked,
        statusChangedAt: DateTime(2026, 3, 1),
        blockedReason: 'waiting on approval',
        statusPendingPush: true,
        externalProvider: 'jira',
        externalId: 'PROJ-123',
        externalUrl: 'https://example.atlassian.net/browse/PROJ-123',
        externalCachedTitle: 'Buy milk (cached)',
        externalLastSyncedAt: DateTime(2026, 2, 28, 10),
      );

      final roundTripped = TaskSupabaseMapper.fromMap(
        TaskSupabaseMapper.toMap(original, includeStatusFields: true),
      );

      expect(roundTripped.id, original.id);
      expect(roundTripped.title, original.title);
      // Wire format round-trips through UTC; compare instants, not
      // local-vs-UTC representations.
      expect(
        roundTripped.scheduledDate!.isAtSameMomentAs(original.scheduledDate!),
        isTrue,
      );
      expect(roundTripped.status, original.status);
      expect(
        roundTripped.statusChangedAt!
            .isAtSameMomentAs(original.statusChangedAt!),
        isTrue,
      );
      expect(roundTripped.completedAt, original.completedAt);
      expect(roundTripped.description, original.description);
      expect(roundTripped.blockedReason, original.blockedReason);
      expect(roundTripped.noteId, original.noteId);
      expect(roundTripped.externalProvider, original.externalProvider);
      expect(roundTripped.externalId, original.externalId);
      expect(roundTripped.externalUrl, original.externalUrl);
      expect(roundTripped.externalCachedTitle, original.externalCachedTitle);
      expect(
        roundTripped.externalLastSyncedAt!
            .isAtSameMomentAs(original.externalLastSyncedAt!),
        isTrue,
      );
      expect(
        roundTripped.createdAt.isAtSameMomentAs(original.createdAt),
        isTrue,
      );
      expect(
        roundTripped.updatedAt.isAtSameMomentAs(original.updatedAt),
        isTrue,
      );
      expect(roundTripped.version, original.version);
      expect(roundTripped.userId, original.userId);
      // The one asymmetry: never emitted outbound, forced false inbound.
      expect(original.statusPendingPush, isTrue);
      expect(roundTripped.statusPendingPush, isFalse);
    });

    test('a backlog task round-trips with scheduledDate staying null', () {
      final backlog = buildTask().copyWith(scheduledDate: null);

      final roundTripped = TaskSupabaseMapper.fromMap(
        TaskSupabaseMapper.toMap(backlog, includeStatusFields: true),
      );

      expect(roundTripped.scheduledDate, isNull);
    });
  });
}
