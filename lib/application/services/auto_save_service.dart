import 'dart:async';

import 'package:flutter/foundation.dart';

import '../use_cases/update_note_use_case.dart';

/// Application service: Auto-save with dirty-flag + debounce + periodic safety net.
///
/// NO save button — saves automatically when the user stops typing.
/// The editor is **100 % decoupled** from the save pipeline:
///
///  1. The page calls [watch] once when loading a note, registering lazy
///     getters for title & content.
///  2. On every keystroke the page calls [markDirty] — a single `bool`
///     assignment plus a debounce reset.
///  3. A debounce timer fires 3 s after the **last** keystroke, triggering
///     the actual save. A periodic safety-net timer also fires every 3 s
///     to guarantee data is persisted during long uninterrupted typing.
///
/// Only persists locally — remote sync is handled on app open/close.
class AutoSaveService {
  final UpdateNoteUseCase _updateNote;

  // ── Timers ─────────────────────────────────────────────────────────
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  static const _checkInterval = Duration(seconds: 3);

  // ── Dirty-flag state ─────────────────────────────────────────────────
  bool _isDirty = false;
  bool _isSaving = false;
  String? _watchedNoteId;
  String Function()? _getTitle;
  String Function()? _getContent;

  /// Callback invoked after a successful save (can be async).
  Future<void> Function(String noteId)? onSaved;

  /// Callback invoked when a save actually starts (for UI indicator).
  VoidCallback? onSaving;

  /// Callback invoked when a save fails (for UI recovery).
  VoidCallback? onError;

  AutoSaveService(this._updateNote);

  // ── Public API ───────────────────────────────────────────────────────

  /// Register a note to watch for auto-saving.
  ///
  /// Call once when loading a note. The [getTitle] and [getContent] closures
  /// are only evaluated when a save is triggered — **never** on the keystroke
  /// itself.
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
  /// Resets the debounce timer so a save is triggered 3 s after the
  /// **last** call — i.e. 3 s after the user stops typing.
  void markDirty() {
    _isDirty = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_checkInterval, _tick);
  }

  /// Stop watching the current note (e.g., before disposing controllers).
  void unwatch() {
    _stopTimer();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _watchedNoteId = null;
    _getTitle = null;
    _getContent = null;
    _isDirty = false;
    _isSaving = false;
  }

  /// Force an immediate save (e.g., when navigating away or disposing).
  ///
  /// Returns `true` if the DB write succeeded.
  Future<bool> forceSave({
    required String noteId,
    String? title,
    String? content,
  }) async {
    _isDirty = false;
    _debounceTimer?.cancel();
    return _performSave(noteId: noteId, title: title, content: content);
  }

  /// Flush the currently watched note using registered lazy getters.
  /// Returns true if a save was performed.
  Future<bool> flushWatched() async {
    if (_watchedNoteId == null) return false;
    _isDirty = false;
    _debounceTimer?.cancel();
    return _performSave(
      noteId: _watchedNoteId!,
      title: _getTitle?.call(),
      content: _getContent?.call(),
    );
  }

  /// Cancel any pending changes without saving.
  void cancel() {
    _isDirty = false;
    _debounceTimer?.cancel();
  }

  /// Dispose resources.
  void dispose() {
    _stopTimer();
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  // ── Internals ────────────────────────────────────────────────────────

  void _startTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_checkInterval, (_) {
      _tick(); // safety-net for long uninterrupted typing sessions
    });
  }

  void _stopTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Silent tick — persists data without calling [onSaved].
  ///
  /// [onSaved] triggers `notifyListeners()` → widget rebuilds, which can
  /// cause phantom dirty-marks from QuillEditor.  Only [forceSave] (called
  /// by the editor's debounce) invokes [onSaved] to refresh the UI list.
  ///
  /// Guards against overlapping saves with [_isSaving]. On failure,
  /// re-marks dirty so the next tick retries automatically.
  void _tick() {
    if (!_isDirty || _watchedNoteId == null || _isSaving) return;
    _isDirty = false;
    _isSaving = true;

    _updateNote
        .execute(
          noteId: _watchedNoteId!,
          title: _getTitle?.call(),
          content: _getContent?.call(),
        )
        .catchError((Object error) {
          debugPrint('[AutoSaveService] Save failed, will retry: $error');
          _isDirty = true;
          onError?.call();
          return null;
        })
        .whenComplete(() {
          _isSaving = false;
        });
  }

  /// Force an immediate save (dispose / navigation).
  ///
  /// Returns `true` if the DB write succeeded, `false` on error.
  Future<bool> _performSave({
    required String noteId,
    String? title,
    String? content,
  }) async {
    try {
      await _updateNote.execute(
        noteId: noteId,
        title: title,
        content: content,
      );
      try {
        await onSaved?.call(noteId);
      } catch (_) {
        // onSaved error is non-critical — data is already persisted.
      }
      return true;
    } catch (e) {
      debugPrint('[AutoSaveService] Force-save failed: $e');
      onError?.call();
      return false;
    }
  }
}
