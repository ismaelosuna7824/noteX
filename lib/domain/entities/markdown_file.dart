import '../value_objects/sync_status.dart';

/// Core domain entity representing a Markdown file.
///
/// This entity is pure — no Flutter, Firebase, or external dependencies.
class MarkdownFile {
  final String id;
  final String title;
  final String content; // Raw markdown string
  final String? projectId; // null = root (no project)
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final int version;
  final DateTime? deletedAt;
  final String? userId;

  const MarkdownFile({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.projectId,
    this.syncStatus = SyncStatus.localOnly,
    this.version = 1,
    this.deletedAt,
    this.userId,
  });

  /// Creates a new empty markdown file.
  factory MarkdownFile.create({
    required String id,
    required String title,
    String content = '',
    String? projectId,
    String? userId,
  }) {
    final now = DateTime.now();
    return MarkdownFile(
      id: id,
      title: title,
      content: content,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
      version: 1,
      syncStatus: SyncStatus.localOnly,
      userId: userId,
    );
  }

  /// Whether this file has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Returns a copy with updated fields.
  MarkdownFile copyWith({
    String? title,
    String? content,
    Object? projectId = const _Unset(),
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    int? version,
    Object? deletedAt = const _Unset(),
    Object? userId = const _Unset(),
  }) {
    return MarkdownFile(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      projectId: projectId is _Unset ? this.projectId : projectId as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      version: version ?? this.version,
      deletedAt: deletedAt is _Unset ? this.deletedAt : deletedAt as DateTime?,
      userId: userId is _Unset ? this.userId : userId as String?,
    );
  }

  /// Marks the file as pending sync after an update.
  MarkdownFile markPendingSync() {
    return copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  /// Marks the file as synced.
  MarkdownFile markSynced() {
    return copyWith(syncStatus: SyncStatus.synced);
  }

  /// Soft-delete this file and mark pending sync.
  MarkdownFile markDeleted() {
    return copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  /// Increment version for optimistic locking.
  MarkdownFile incrementVersion() {
    return copyWith(version: version + 1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MarkdownFile && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MarkdownFile(id: $id, title: $title)';
}

// Private sentinel for nullable copyWith fields.
class _Unset {
  const _Unset();
}
