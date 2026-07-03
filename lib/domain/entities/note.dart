import 'dart:convert';

import '../value_objects/sync_status.dart';

/// Core domain entity representing a note.
///
/// This entity is pure — no Flutter, Firebase, or external dependencies.
/// All business rules related to notes are encapsulated here.
class Note {
  final String id;
  final String title;
  final String content; // Markdown (legacy notes may still be Quill Delta JSON until migrated)
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
  final bool isLocked;

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
    this.isLocked = false,
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
      content: '', // Empty Markdown body (legacy empty was the Delta '[]')
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
  /// Tolerates BOTH content formats during the Delta→Markdown migration:
  /// - Legacy Quill Delta: empty when the string is `'[]'` or contains only
  ///   whitespace / newline operations like `[{"insert":"\n"}]`.
  /// - Markdown: empty when its stripped plaintext has no real text.
  /// The title is irrelevant — even a custom title with no body is empty.
  ///
  /// DATA SAFETY: this biases HARD toward NOT-empty. A false "empty" would let
  /// [CleanupEmptyNotesUseCase] hard-delete a note, so on any doubt we return
  /// `false`. A false "not-empty" merely skips cleanup, which is harmless.
  bool get isEmpty {
    if (content == '[]') return true;
    if (content.trim().isEmpty) return true;

    final delta = _tryDecodeDelta(content);
    if (delta != null) {
      // Legacy Quill Delta path (unchanged heuristic).
      if (delta.isEmpty) return true;
      if (delta.length == 1) {
        final op = delta[0];
        if (op is Map && op.length == 1 && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String && insert.trim().isEmpty) return true;
        }
      }
      return false;
    }

    // Markdown path: empty only when the stripped plaintext is blank.
    try {
      return _stripMarkdown(content).trim().isEmpty;
    } catch (_) {
      // Never let a stripping failure delete a note.
      return false;
    }
  }

  /// Total word count of the note body. Tolerates both formats; never throws.
  int get wordCount {
    final delta = _tryDecodeDelta(content);
    if (delta != null) {
      final buffer = StringBuffer();
      for (final op in delta) {
        if (op is Map && op['insert'] is String) {
          buffer.write(op['insert']);
        }
      }
      return _countWords(buffer.toString());
    }
    try {
      return _countWords(_stripMarkdown(content));
    } catch (_) {
      return 0;
    }
  }

  /// Extracts a plain-text preview from the note body (first ~200 chars).
  /// Tolerates both formats; never throws.
  String get plainTextPreview {
    final delta = _tryDecodeDelta(content);
    if (delta != null) {
      final buffer = StringBuffer();
      for (final op in delta) {
        if (op is Map && op['insert'] is String) {
          buffer.write(op['insert']);
          if (buffer.length > 200) break;
        }
      }
      final text = buffer.toString().trim();
      return text.length > 200 ? text.substring(0, 200) : text;
    }
    try {
      final stripped =
          _stripMarkdown(content).replaceAll(RegExp(r'\s+'), ' ').trim();
      return stripped.length > 200 ? stripped.substring(0, 200) : stripped;
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
    bool? isLocked,
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
      isLocked: isLocked ?? this.isLocked,
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

// --- Pure content helpers -------------------------------------------------
//
// Lightweight, dependency-free format handling kept INSIDE the domain so the
// entity never has to import an infrastructure converter (which would invert
// the Hexagonal dependency direction). Detection mirrors the read-path rule:
// a legacy Quill Delta document is a JSON array of ops; everything else is
// treated as Markdown.

/// Attempts to decode [content] as a legacy Quill Delta document.
///
/// Returns the decoded op list when [content] is a JSON array (Delta), or
/// `null` when it is not and should be treated as Markdown. Never throws.
List<dynamic>? _tryDecodeDelta(String content) {
  final trimmed = content.trim();
  if (!trimmed.startsWith('[')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is List ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Counts whitespace-separated words in [text]. Empty/blank → 0.
int _countWords(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

/// Approximates the plain text of a Markdown string by stripping common
/// syntax markers while KEEPING the underlying words. This is intentionally
/// forgiving: it is used to decide emptiness and build previews, not to render
/// content, so leftover punctuation only biases toward "has text" (the safe
/// direction for cleanup). Pure string logic — no dependencies, never throws.
String _stripMarkdown(String markdown) {
  var text = markdown;
  // Fenced code-block markers (``` or ```lang) — keep the code text.
  text = text.replaceAll(RegExp(r'```[^\n]*'), '');
  // Images: ![alt](url) -> alt
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  // Links: [text](url) -> text
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  );
  // Task-list checkboxes: "- [ ] " / "- [x] " markers at line start.
  text = text.replaceAll(
    RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s*', multiLine: true),
    '',
  );
  // Bullet / ordered list markers at line start.
  text = text.replaceAll(
    RegExp(r'^\s*(?:[-*+]|\d+\.)\s+', multiLine: true),
    '',
  );
  // Blockquote markers at line start.
  text = text.replaceAll(RegExp(r'^\s*>+\s?', multiLine: true), '');
  // ATX headers at line start.
  text = text.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
  // Horizontal rules (---, ***, ___).
  text = text.replaceAll(
    RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$', multiLine: true),
    '',
  );
  // Emphasis / bold / strikethrough markers.
  text = text.replaceAll(RegExp(r'\*\*\*|\*\*|\*|___|__|_|~~'), '');
  // Inline code backticks.
  text = text.replaceAll('`', '');
  return text;
}
