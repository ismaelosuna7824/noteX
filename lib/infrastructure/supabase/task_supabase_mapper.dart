import '../../domain/entities/task.dart';
import '../../domain/value_objects/sync_status.dart';
import '../../domain/value_objects/task_status_resolution.dart';

/// Pure static mapping between [Task] and its Supabase (`reminders` table)
/// wire representation.
///
/// Extracted from [SupabaseSyncAdapter] so the bidirectional compatibility
/// contract (M4, M5, M8) can be unit-tested without a live `SupabaseClient`
/// — see design D6.
class TaskSupabaseMapper {
  const TaskSupabaseMapper._();

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);

  /// Builds the outbound payload from write intent, not the whole entity
  /// (design D10).
  ///
  /// R1 — the status quartet (`status`, `is_completed`, `completed_at`,
  /// `status_changed_at`) travels as a unit and is included only when
  /// [includeStatusFields] is true (a transition-originated write). This is
  /// what keeps the `status_changed_at` marker monotonic: every other write
  /// omits all four keys, and PostgREST leaves omitted columns untouched.
  ///
  /// R2 — a null `status_changed_at` is never emitted, even when the rest
  /// of the quartet is included. This closes the null-erasure channel only;
  /// it is not a general backstop for an R1 violation (a stale non-null
  /// timestamp would still regress the marker).
  static Map<String, dynamic> toMap(
    Task t, {
    required bool includeStatusFields,
  }) {
    return {
      'id': t.id,
      'user_id': t.userId,
      'title': t.title,
      'scheduled_date': t.scheduledDate.toUtc().toIso8601String(),
      'description': t.description,
      'blocked_reason': t.blockedReason,
      'note_id': t.noteId,
      'external_provider': t.externalProvider,
      'external_id': t.externalId,
      'external_url': t.externalUrl,
      'external_cached_title': t.externalCachedTitle,
      'external_last_synced_at':
          t.externalLastSyncedAt?.toUtc().toIso8601String(),
      'created_at': t.createdAt.toUtc().toIso8601String(),
      'updated_at': t.updatedAt.toUtc().toIso8601String(),
      'deleted_at': t.deletedAt?.toUtc().toIso8601String(),
      'version': t.version,
      'sync_status': 'synced',
      if (includeStatusFields) ...{
        'status': t.status.name,
        'is_completed': t.isDone,
        'completed_at': t.completedAt?.toUtc().toIso8601String(),
        if (t.statusChangedAt != null)
          'status_changed_at': t.statusChangedAt!.toUtc().toIso8601String(),
      },
    };
  }

  /// Parses an inbound Supabase row.
  ///
  /// Every v18 field is parsed defensively (`as X?`) so a row written by a
  /// client predating that column reads as null rather than throwing.
  /// `statusPendingPush` is always false — the status in this row came
  /// from remote, not from a local transition awaiting push.
  static Task fromMap(Map<String, dynamic> m) {
    final statusChangedAt = _parseUtc(m['status_changed_at']);
    final resolution = TaskStatusResolution.fromStorage(
      m['status'] as String?,
      isCompleted: m['is_completed'] as bool? ?? false,
      completedAt: _parseUtc(m['completed_at']),
      statusChangedAt: statusChangedAt,
    );

    return Task(
      id: m['id'] as String,
      title: m['title'] as String? ?? '',
      scheduledDate: DateTime.parse(m['scheduled_date'] as String),
      status: resolution.status,
      statusChangedAt: statusChangedAt,
      statusPendingPush: false,
      completedAt: resolution.completedAt,
      description: m['description'] as String? ?? '',
      blockedReason: m['blocked_reason'] as String?,
      noteId: m['note_id'] as String?,
      externalProvider: m['external_provider'] as String?,
      externalId: m['external_id'] as String?,
      externalUrl: m['external_url'] as String?,
      externalCachedTitle: m['external_cached_title'] as String?,
      externalLastSyncedAt: _parseUtc(m['external_last_synced_at']),
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
      syncStatus: SyncStatus.synced,
      version: m['version'] as int? ?? 1,
      deletedAt: m['deleted_at'] != null
          ? DateTime.parse(m['deleted_at'] as String)
          : null,
      userId: m['user_id'] as String?,
    );
  }
}
