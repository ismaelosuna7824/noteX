import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/task.dart';
import 'package:notex/domain/value_objects/sync_status.dart';
import 'package:notex/domain/value_objects/task_status.dart';
import 'package:notex/infrastructure/supabase/task_supabase_mapper.dart';

/// Named marker-regression test (design D2/D10) — keeps R1 from being
/// "simplified" away.
///
/// Replays the three-device sequence that motivated D10 at the mapper
/// level:
///
///  1. Device B (new) completes task T -> remote `status='done'`,
///     `is_completed=true`, `completed_at=T1`.
///  2. B moves T back to `doing` -> remote `status='doing'`,
///     `is_completed=false`, `status_changed_at=T2 > T1`.
///  3. Device C (new, but has not pulled since step 1) still holds a local
///     copy from before the transition — its local `status_changed_at` is
///     stale/absent relative to remote. The user edits T's title on C: a
///     **non-transition** write (`statusPendingPush == false`).
///
/// The payload C's non-transition write produces must contain neither
/// `status` nor `status_changed_at` — otherwise C's stale (or absent)
/// marker would overwrite remote's `status_changed_at = T2`, and a later
/// stale `is_completed: true` from a fourth, older device could pass M8's
/// gate and strand the task back in `done`.
void main() {
  test(
    'a non-transition write payload contains neither status nor '
    'status_changed_at',
    () {
      // Device C's local, stale copy: it has a status (from before the
      // remote transition) but the write in question is a title edit, not
      // a transition — statusPendingPush is false.
      final staleLocalCopy = Task(
        id: 'task-1',
        title: 'Old title',
        scheduledDate: DateTime(2026, 3, 4),
        status: TaskStatus.done,
        statusChangedAt: DateTime(2026, 3, 1), // T1, now stale
        statusPendingPush: false,
        completedAt: DateTime(2026, 3, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.pendingSync,
      );

      final titleEdited = staleLocalCopy.copyWith(
        title: 'Edited title',
        updatedAt: DateTime(2026, 3, 5),
      );
      // A title edit must not flip statusPendingPush — only transitionTo
      // does that.
      expect(titleEdited.statusPendingPush, isFalse);

      final payload = TaskSupabaseMapper.toMap(
        titleEdited,
        includeStatusFields: titleEdited.statusPendingPush,
      );

      expect(payload.containsKey('status'), isFalse);
      expect(payload.containsKey('status_changed_at'), isFalse);
      expect(payload.containsKey('is_completed'), isFalse);
      expect(payload.containsKey('completed_at'), isFalse);
      // The edit itself is still carried.
      expect(payload['title'], 'Edited title');
    },
  );

  test(
    'a transition write, in contrast, always carries a fresh '
    'status_changed_at',
    () {
      final task = Task(
        id: 'task-1',
        title: 'Buy milk',
        scheduledDate: DateTime(2026, 3, 4),
        status: TaskStatus.done,
        statusChangedAt: DateTime(2026, 3, 1),
        completedAt: DateTime(2026, 3, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.synced,
      );

      final reopened = task.transitionTo(TaskStatus.doing);
      expect(reopened.statusPendingPush, isTrue);

      final payload = TaskSupabaseMapper.toMap(
        reopened,
        includeStatusFields: reopened.statusPendingPush,
      );

      expect(payload['status'], 'doing');
      expect(payload.containsKey('status_changed_at'), isTrue);
      expect(payload['is_completed'], isFalse);
    },
  );
}
