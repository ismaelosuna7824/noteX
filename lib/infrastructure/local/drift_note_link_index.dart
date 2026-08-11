import 'package:drift/drift.dart';

import '../../domain/repositories/note_link_index.dart';
import '../../domain/value_objects/note_link.dart';
import 'database.dart';

/// Infrastructure adapter: implements NoteLinkIndex using Drift (SQLite).
///
/// Purely local — the `note_links` table is excluded from cloud sync by design
/// (see the table's declaration in `database.dart`).
class DriftNoteLinkIndex implements NoteLinkIndex {
  final AppDatabase _db;

  DriftNoteLinkIndex(this._db);

  static NoteLink _toDomain(NoteLinkRow row) => NoteLink(
        sourceNoteId: row.sourceNoteId,
        targetNoteId: row.targetNoteId,
        displayText: row.displayText,
      );

  @override
  Future<void> replaceLinksFrom(
    String sourceNoteId,
    List<NoteLink> links,
  ) async {
    // Delete-then-insert inside one transaction: a note's outgoing edges are
    // replaced wholesale, so a partial write must never be observable.
    await _db.transaction(() async {
      await (_db.delete(_db.noteLinks)
            ..where((t) => t.sourceNoteId.equals(sourceNoteId)))
          .go();

      if (links.isEmpty) return;

      await _db.batch((batch) {
        batch.insertAll(
          _db.noteLinks,
          links.map(
            (link) => NoteLinksCompanion.insert(
              sourceNoteId: link.sourceNoteId,
              targetNoteId: link.targetNoteId,
              displayText: Value(link.displayText),
            ),
          ),
        );
      });
    });
  }

  @override
  Future<List<NoteLink>> outgoingFrom(String sourceNoteId) async {
    final rows = await (_db.select(_db.noteLinks)
          ..where((t) => t.sourceNoteId.equals(sourceNoteId)))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<NoteLink>> backlinksTo(String targetNoteId) async {
    final rows = await (_db.select(_db.noteLinks)
          ..where((t) => t.targetNoteId.equals(targetNoteId)))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<void> removeNote(String noteId) async {
    await (_db.delete(_db.noteLinks)
          ..where((t) =>
              t.sourceNoteId.equals(noteId) | t.targetNoteId.equals(noteId)))
        .go();
  }

  @override
  Future<int> count() async {
    final countExp = _db.noteLinks.sourceNoteId.count();
    final query = _db.selectOnly(_db.noteLinks)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.noteLinks).go();
  }
}
