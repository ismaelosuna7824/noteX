import '../value_objects/sync_status.dart';

/// Core domain entity representing a note.
///
/// This entity is pure — no Flutter, Firebase, or external dependencies.
/// All business rules related to notes are encapsulated here.
class Note {
  final String id;
  final String title;
  final String content; // Quill Delta JSON string
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final String? backgroundImage;
  final String? themeId;
  final bool isPinned;
  final int version;
  final DateTime? deletedAt;
  final String? userId;
  final String? projectId;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.localOnly,
    this.backgroundImage,
    this.themeId,
    this.isPinned = false,
    this.version = 1,
    this.deletedAt,
    this.userId,
    this.projectId,
  });

  /// Creates a new empty note for today.
  factory Note.createDaily({
    required String id,
    String? backgroundImage,
    String? themeId,
    String? userId,
    String? projectId,
  }) {
    final now = DateTime.now();
    return Note(
      id: id,
      title: _defaultTitleForDate(now),
      content: '[]', // Empty Quill Delta
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.localOnly,
      backgroundImage: backgroundImage,
      themeId: themeId,
      isPinned: false,
      version: 1,
      userId: userId,
      projectId: projectId,
    );
  }

  /// Whether this note has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Returns a copy with updated fields.
  Note copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    String? backgroundImage,
    String? themeId,
    bool? isPinned,
    int? version,
    Object? deletedAt = const _Unset(),
    Object? userId = const _Unset(),
    Object? projectId = const _Unset(),
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      themeId: themeId ?? this.themeId,
      isPinned: isPinned ?? this.isPinned,
      version: version ?? this.version,
      deletedAt: deletedAt is _Unset ? this.deletedAt : deletedAt as DateTime?,
      userId: userId is _Unset ? this.userId : userId as String?,
      projectId:
          projectId is _Unset ? this.projectId : projectId as String?,
    );
  }

  /// Marks the note as pending sync after an update.
  Note markPendingSync() {
    return copyWith(
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  /// Marks the note as synced.
  Note markSynced() {
    return copyWith(syncStatus: SyncStatus.synced);
  }

  /// Soft-delete this note and mark pending sync.
  Note markDeleted() {
    return copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pendingSync,
    );
  }

  /// Increment version for optimistic locking.
  Note incrementVersion() {
    return copyWith(version: version + 1);
  }

  /// Check if this note belongs to a specific date.
  bool isForDate(DateTime date) {
    return createdAt.year == date.year &&
        createdAt.month == date.month &&
        createdAt.day == date.day;
  }

  static String _defaultTitleForDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Note && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Note(id: $id, title: $title)';
}

// Private sentinel for nullable copyWith fields.
class _Unset {
  const _Unset();
}
