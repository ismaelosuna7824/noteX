import 'dart:async';
import 'dart:convert';

import '../use_cases/update_note_use_case.dart';
import '../use_cases/cleanup_empty_notes_use_case.dart';
import 'sync_engine.dart';

/// Application service: Auto-save with intelligent debounce.
///
/// NO save button — saves automatically when the user stops typing.
/// Uses an 800ms debounce to avoid saving on every keystroke.
class AutoSaveService {
  final UpdateNoteUseCase _updateNote;
  final SyncEngine _syncEngine;
  final CleanupEmptyNotesUseCase _cleanupEmptyNotes;

  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 800);

  /// Callback invoked after a successful save (can be async).
  Future<void> Function(String noteId)? onSaved;

  /// Callback invoked when an empty note is cleaned up on navigate-away.
  Future<void> Function(String noteId)? onNoteDeleted;

  AutoSaveService(this._updateNote, this._syncEngine, this._cleanupEmptyNotes);

  /// Schedule an auto-save for the given note.
  /// Resets the debounce timer on each call.
  void scheduleAutoSave({
    required String noteId,
    String? title,
    String? content,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      await _performSave(noteId: noteId, title: title, content: content);
    });
  }

  /// Force an immediate save (e.g., when navigating away).
  ///
  /// If the note is still empty, it is deleted instead of saved so
  /// the user doesn't accumulate blank notes.
  Future<void> forceSave({
    required String noteId,
    String? title,
    String? content,
  }) async {
    _debounceTimer?.cancel();

    // Empty note → clean up instead of saving
    if (_isEmptyContent(content) && _isDefaultTitle(title)) {
      final wasDeleted = await _cleanupEmptyNotes.executeForNote(noteId);
      if (wasDeleted) {
        await onNoteDeleted?.call(noteId);
      }
      return;
    }

    await _performSave(noteId: noteId, title: title, content: content);
  }

  Future<void> _performSave({
    required String noteId,
    String? title,
    String? content,
  }) async {
    // Skip persisting if the note is still empty
    if (_isEmptyContent(content) && _isDefaultTitle(title)) return;

    final updated = await _updateNote.execute(
      noteId: noteId,
      title: title,
      content: content,
    );

    if (updated != null) {
      await onSaved?.call(noteId);
      // Trigger sync if authenticated
      await _syncEngine.syncIfAuthenticated();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Quick content-emptiness check without needing the full Note entity.
  static bool _isEmptyContent(String? content) {
    if (content == null || content == '[]') return true;
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

  /// Quick default-title check matching the date format "Month DD, YYYY".
  static bool _isDefaultTitle(String? title) {
    if (title == null || title.isEmpty) return true;
    return RegExp(
      r'^(January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}$',
    ).hasMatch(title);
  }

  /// Cancel any pending auto-save.
  void cancel() {
    _debounceTimer?.cancel();
  }

  /// Dispose resources.
  void dispose() {
    _debounceTimer?.cancel();
  }
}
