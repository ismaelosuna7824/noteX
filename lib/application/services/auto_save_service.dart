import 'dart:async';

import '../use_cases/update_note_use_case.dart';

/// Application service: Auto-save with dirty-flag + periodic timer.
///
/// NO save button — saves automatically when the user stops typing.
/// The editor is **100 % decoupled** from the save pipeline:
///
///  1. The page calls [watch] once when loading a note, registering lazy
///     getters for title & content.
///  2. On every keystroke the page calls [markDirty] — a single `bool`
///     assignment with **zero** overhead on the UI thread.
///  3. A periodic timer (every 3 s) checks the flag. If dirty it reads
///     the getters, serialises, and persists to the local Drift database.
///
/// Only persists locally — remote sync is handled on app open/close.
class AutoSaveService {
  final UpdateNoteUseCase _updateNote;

  // ── Periodic timer ───────────────────────────────────────────────────
  Timer? _periodicTimer;
  static const _checkInterval = Duration(seconds: 3);

  // ── Dirty-flag state ─────────────────────────────────────────────────
  bool _isDirty = false;
  String? _watchedNoteId;
  String Function()? _getTitle;
  String Function()? _getContent;

  /// Callback invoked after a successful save (can be async).
  Future<void> Function(String noteId)? onSaved;

  AutoSaveService(this._updateNote);

  // ── Public API ───────────────────────────────────────────────────────

  /// Register a note to watch for auto-saving.
  ///
  /// Call once when loading a note. The [getTitle] and [getContent] closures
  /// are only evaluated when the periodic timer detects unsaved changes —
  /// **never** on the keystroke itself.
  void watch({
    required String noteId,
    required String Function() getTitle,
    required String Function() getContent,
  }) {
    _watchedNoteId = noteId;
    _getTitle = getTitle;
    _getContent = getContent;
    _isDirty = false;
    _startTimer();
  }

  /// Mark the current note as having unsaved changes.
  ///
  /// Cost: a single boolean assignment — zero overhead on the UI thread.
  void markDirty() {
    _isDirty = true;
  }

  /// Stop watching the current note (e.g., before disposing controllers).
  void unwatch() {
    _stopTimer();
    _watchedNoteId = null;
    _getTitle = null;
    _getContent = null;
    _isDirty = false;
  }

  /// Force an immediate save (e.g., when navigating away or disposing).
  Future<void> forceSave({
    required String noteId,
    String? title,
    String? content,
  }) async {
    _isDirty = false;
    await _performSave(noteId: noteId, title: title, content: content);
  }

  /// Cancel any pending changes without saving.
  void cancel() {
    _isDirty = false;
  }

  /// Dispose resources.
  void dispose() {
    _stopTimer();
  }

  // ── Internals ────────────────────────────────────────────────────────

  void _startTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_checkInterval, (_) {
      _tick(); // synchronous entry — avoids unawaited-Future issues
    });
  }

  void _stopTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Non-async tick — uses `.whenComplete` so [onSaved] fires regardless
  /// of whether the DB call succeeds, fails, or throws.
  void _tick() {
    if (!_isDirty || _watchedNoteId == null) return;
    _isDirty = false;

    final noteId = _watchedNoteId!;
    _updateNote
        .execute(
          noteId: noteId,
          title: _getTitle?.call(),
          content: _getContent?.call(),
        )
        .whenComplete(() => onSaved?.call(noteId));
  }

  /// Force an immediate save (dispose / navigation).
  Future<void> _performSave({
    required String noteId,
    String? title,
    String? content,
  }) async {
    await _updateNote.execute(
      noteId: noteId,
      title: title,
      content: content,
    );
    await onSaved?.call(noteId);
  }
}
