import '../value_objects/note_link.dart';

/// Port (interface) for the note link index.
///
/// This is the domain's contract — infrastructure adapters must implement this.
///
/// Unlike the other ports in this package the index stores **derived** state:
/// every row is reproducible by re-parsing note content with `NoteLinkParser`.
/// Implementations must therefore be safe to wipe and rebuild, and must never
/// participate in cloud sync — replicating derivable rows would only invent
/// conflicts between devices that already agree on the note bodies.
abstract class NoteLinkIndex {
  /// Replace every outgoing link recorded for [sourceNoteId] with [links].
  ///
  /// Called after a note is saved. Passing an empty list clears the note's
  /// outgoing edges without touching links that point *at* it.
  Future<void> replaceLinksFrom(String sourceNoteId, List<NoteLink> links);

  /// Links whose body lives in [sourceNoteId] — what this note points at.
  Future<List<NoteLink>> outgoingFrom(String sourceNoteId);

  /// Links pointing at [targetNoteId] — what points at this note.
  Future<List<NoteLink>> backlinksTo(String targetNoteId);

  /// Drop every edge touching [noteId], in either direction.
  ///
  /// Called when a note is deleted for good, so the graph keeps no dangling
  /// edges. Soft-deleted (trashed) notes are left indexed: restoring one should
  /// bring its links back with it.
  Future<void> removeNote(String noteId);

  /// Number of edges currently indexed. Intended for diagnostics and for
  /// deciding whether a first-run rebuild is needed.
  Future<int> count();

  /// Wipe the whole index. Safe by construction — it is rebuilt from content.
  Future<void> clear();
}
