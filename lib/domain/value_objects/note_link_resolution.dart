import '../entities/note.dart';

/// The three affordance states for a task's linked note (design D9, spec
/// capability `task-note-linking`).
enum NoteLinkStatus {
  /// The linked note exists and is not in the trash — open it.
  found,

  /// The linked note exists but has been soft-deleted — offer to restore.
  /// The link itself is preserved (no cascade, no silent clear).
  inTrash,

  /// No note exists for this id (permanently deleted, or the id is stale) —
  /// offer to clear the link. Expected, not an error: `noteId` carries no
  /// foreign key (design D9).
  missing,
}

/// Result of resolving a task's `noteId` into one of the three affordance
/// states above.
class NoteLinkResolution {
  final NoteLinkStatus status;

  /// The resolved note. Present for [NoteLinkStatus.found] and
  /// [NoteLinkStatus.inTrash]; null for [NoteLinkStatus.missing].
  final Note? note;

  const NoteLinkResolution(this.status, this.note);
}
