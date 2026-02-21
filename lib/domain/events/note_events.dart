import '../entities/note.dart';

/// Base class for all note-related domain events.
sealed class NoteEvent {
  final DateTime occurredAt;
  const NoteEvent({required this.occurredAt});
}

/// Fired when a new note is created.
class NoteCreated extends NoteEvent {
  final Note note;
  const NoteCreated({required this.note, required super.occurredAt});
}

/// Fired when a note is updated (content, title, etc.).
class NoteUpdated extends NoteEvent {
  final Note note;
  const NoteUpdated({required this.note, required super.occurredAt});
}

/// Fired when a note has been successfully synced.
class NoteSynced extends NoteEvent {
  final Note note;
  const NoteSynced({required this.note, required super.occurredAt});
}

/// Fired when a note is deleted.
class NoteDeleted extends NoteEvent {
  final String noteId;
  const NoteDeleted({required this.noteId, required super.occurredAt});
}
