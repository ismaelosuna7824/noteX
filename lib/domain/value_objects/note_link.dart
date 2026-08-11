/// A single outgoing link from one note to another.
///
/// Links are *derived* data: they are parsed out of a note's Markdown body and
/// can always be rebuilt from it. No link is ever authoritative — if the index
/// holding these is lost, re-parsing every note reproduces it exactly.
class NoteLink {
  /// Id of the note whose body contains the link.
  final String sourceNoteId;

  /// Id of the note the link points at.
  final String targetNoteId;

  /// The text the reader sees — the `[display]` part of the Markdown link.
  ///
  /// Kept for rendering backlink lists without loading the source note body.
  /// It is a snapshot of the link text, not the target note's current title.
  final String displayText;

  const NoteLink({
    required this.sourceNoteId,
    required this.targetNoteId,
    required this.displayText,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteLink &&
          sourceNoteId == other.sourceNoteId &&
          targetNoteId == other.targetNoteId &&
          displayText == other.displayText;

  @override
  int get hashCode => Object.hash(sourceNoteId, targetNoteId, displayText);

  @override
  String toString() =>
      'NoteLink($sourceNoteId -> $targetNoteId, "$displayText")';
}
