import 'dart:convert';

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
  final String? color; // Hex string e.g. "FF6C5CE7"
  final bool isPinned;
  final int version;
  final DateTime? deletedAt;
  final String? userId;
  final String? projectId;
  final String? shareToken;
  final DateTime? sharedAt;
  final bool isEphemeral;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.localOnly,
    this.backgroundImage,
    this.themeId,
    this.color,
    this.isPinned = false,
    this.version = 1,
    this.deletedAt,
    this.userId,
    this.projectId,
    this.shareToken,
    this.sharedAt,
    this.isEphemeral = false,
  });

  /// Creates a new empty note for a given [date] (defaults to today).
  ///
  /// When [date] comes from an external source (e.g. table_calendar) it may
  /// be UTC midnight, which can shift to the previous day after Drift stores
  /// and reads it back as local time.  We normalise to **local noon** so the
  /// day component survives any timezone conversion.
  factory Note.createDaily({
    required String id,
    String? backgroundImage,
    String? themeId,
    String? userId,
    String? projectId,
    DateTime? date,
    bool isEphemeral = false,
  }) {
    final DateTime targetDate;
    if (date != null) {
      // Normalise to local time at noon — safe against timezone shifts
      targetDate = DateTime(date.year, date.month, date.day, 12, 0, 0);
    } else {
      targetDate = DateTime.now();
    }
    return Note(
      id: id,
      title: _defaultTitleForDate(targetDate),
      content: '[]', // Empty Quill Delta
      createdAt: targetDate,
      updatedAt: targetDate,
      syncStatus: SyncStatus.localOnly,
      backgroundImage: backgroundImage,
      themeId: themeId,
      isPinned: false,
      version: 1,
      userId: userId,
      projectId: projectId,
      isEphemeral: isEphemeral,
    );
  }

  /// Whether this note has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Whether this ephemeral note has expired (older than 24 hours).
  bool get isExpired =>
      isEphemeral && DateTime.now().difference(createdAt).inHours >= 24;

  /// Whether this note has no meaningful content in the editor.
  ///
  /// A note is considered empty when the Quill Delta is `'[]'` or contains
  /// only whitespace / newline operations like `[{"insert":"\n"}]`.
  /// The title is irrelevant — even a custom title with no body is empty.
  bool get isEmpty {
    if (content == '[]') return true;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! List || decoded.isEmpty) return true;
      if (decoded.length == 1) {
        final op = decoded[0];
        if (op is Map && op.length == 1 && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String && insert.trim().isEmpty) return true;
        }
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Extracts a plain-text preview from the Quill Delta JSON content.
  /// Returns the first ~200 characters, skipping embeds.
  String get plainTextPreview {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! List) return '';
      final buffer = StringBuffer();
      for (final op in decoded) {
        if (op is Map && op['insert'] is String) {
          buffer.write(op['insert']);
          if (buffer.length > 200) break;
        }
      }
      final text = buffer.toString().trim();
      return text.length > 200 ? text.substring(0, 200) : text;
    } catch (_) {
      return '';
    }
  }

  /// Returns a copy with updated fields.
  Note copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    String? backgroundImage,
    String? themeId,
    Object? color = const _Unset(),
    bool? isPinned,
    int? version,
    Object? deletedAt = const _Unset(),
    Object? userId = const _Unset(),
    Object? projectId = const _Unset(),
    Object? shareToken = const _Unset(),
    Object? sharedAt = const _Unset(),
    bool? isEphemeral,
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
      color: color is _Unset ? this.color : color as String?,
      isPinned: isPinned ?? this.isPinned,
      version: version ?? this.version,
      deletedAt: deletedAt is _Unset ? this.deletedAt : deletedAt as DateTime?,
      userId: userId is _Unset ? this.userId : userId as String?,
      projectId:
          projectId is _Unset ? this.projectId : projectId as String?,
      shareToken:
          shareToken is _Unset ? this.shareToken : shareToken as String?,
      sharedAt:
          sharedAt is _Unset ? this.sharedAt : sharedAt as DateTime?,
      isEphemeral: isEphemeral ?? this.isEphemeral,
    );
  }

  /// Marks the note as pending sync after an update.
  /// Ephemeral notes always stay localOnly.
  Note markPendingSync() {
    if (isEphemeral) {
      return copyWith(updatedAt: DateTime.now());
    }
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
  /// Ephemeral notes stay localOnly.
  Note markDeleted() {
    return copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: isEphemeral ? SyncStatus.localOnly : SyncStatus.pendingSync,
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
