import 'dart:convert';

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
      // Null for a backlog task — see design D5. Requires the remote column
      // to already be nullable (v19 DDL) before a client can push this.
      'scheduled_date': t.scheduledDate?.toUtc().toIso8601String(),
      'description': t.description,
      'blocked_reason': t.blockedReason,
      // v20 (decision architecture/task-note-linking-model) — a task links
      // to N notes, JSON-encoded as text, the same shape as the local
      // column. Deliberately no `note_id` key: this branch carries no
      // backward-compatibility burden (see the decision record — no
      // released client has ever read or written `note_id`), so there is
      // no dual-write. Requires the remote `note_ids` column to exist
      // (v20 DDL) before a client can push this.
      'note_ids': jsonEncode(t.noteIds),
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
      // Parsed defensively (`_parseUtc`, matching every other v18 field):
      // a null `scheduled_date` — legal since v19 — is a backlog task, not
      // a parse error. See design D5's "bounded degradation" note.
      scheduledDate: _parseUtc(m['scheduled_date']),
      status: resolution.status,
      statusChangedAt: statusChangedAt,
      statusPendingPush: false,
      completedAt: resolution.completedAt,
      description: m['description'] as String? ?? '',
      blockedReason: m['blocked_reason'] as String?,
      // Parsed defensively — a row written before the v20 DDL lands (or by
      // an older, unreleased build) has no `note_ids` key at all, which
      // must read as "no links", not a parse error.
      noteIds: _decodeNoteIds(m['note_ids']),
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

  /// Decodes an inbound `note_ids` value into a `List<String>`. Defensive:
  /// missing key, null, malformed JSON, or a JSON value that isn't a list
  /// of strings all degrade to "no links" rather than throwing — matching
  /// every other v18/v19/v20 field's defensive-parse convention on this
  /// inbound path.
  static List<String> _decodeNoteIds(dynamic value) {
    if (value == null) return const [];
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // Malformed JSON — degrade to "no links" rather than crash.
    }
    return const [];
  }
}
