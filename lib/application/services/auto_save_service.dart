import 'dart:async';

import '../use_cases/update_note_use_case.dart';

/// Application service: Auto-save with intelligent debounce.
///
/// NO save button — saves automatically when the user stops typing.
/// Uses an 800ms debounce to avoid saving on every keystroke.
/// Only persists to the local Drift database — remote sync is handled
/// separately on app open/close to avoid excessive Supabase calls.
///
/// [scheduleAutoSave] accepts **lazy getters** so expensive operations like
/// `jsonEncode(delta)` only run when the timer actually fires (after the
/// user pauses typing), not on every single keystroke.
class AutoSaveService {
  final UpdateNoteUseCase _updateNote;

  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 800);

  /// Callback invoked after a successful save (can be async).
  Future<void> Function(String noteId)? onSaved;

  AutoSaveService(this._updateNote);

  /// Schedule an auto-save for the given note.
  /// Resets the debounce timer on each call.
  ///
  /// [getTitle] and [getContent] are evaluated lazily — only when the
  /// 800 ms debounce elapses. This avoids serialising the entire Quill
  /// document on every keystroke, which would block the UI thread.
  void scheduleAutoSave({
    required String noteId,
    required String Function() getTitle,
    required String Function() getContent,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      await _performSave(
        noteId: noteId,
        title: getTitle(),
        content: getContent(),
      );
    });
  }

  /// Force an immediate save (e.g., when navigating away).
  Future<void> forceSave({
    required String noteId,
    String? title,
    String? content,
  }) async {
    _debounceTimer?.cancel();
    await _performSave(noteId: noteId, title: title, content: content);
  }

  Future<void> _performSave({
    required String noteId,
    String? title,
    String? content,
  }) async {
    final updated = await _updateNote.execute(
      noteId: noteId,
      title: title,
      content: content,
    );

    if (updated != null) {
      await onSaved?.call(noteId);
    }
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
