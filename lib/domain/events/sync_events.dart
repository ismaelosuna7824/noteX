import '../value_objects/sync_result.dart';

/// Base class for all sync-related domain events.
sealed class SyncEvent {
  final DateTime occurredAt;
  const SyncEvent({required this.occurredAt});
}

/// Fired when any entity is created/updated/deleted locally and needs sync.
class EntityChanged extends SyncEvent {
  final String entityType; // 'notes', 'projects', 'time_entries'
  final String entityId;
  const EntityChanged({
    required this.entityType,
    required this.entityId,
    required super.occurredAt,
  });
}

/// Fired when a sync cycle completes.
class SyncCompleted extends SyncEvent {
  final SyncResult result;
  const SyncCompleted({required this.result, required super.occurredAt});
}

/// Fired when a sync cycle fails.
class SyncFailed extends SyncEvent {
  final String error;
  const SyncFailed({required this.error, required super.occurredAt});
}
