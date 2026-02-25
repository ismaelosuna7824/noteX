import 'dart:async';

import '../use_cases/markdown/update_markdown_file_use_case.dart';

/// Application service: Auto-save for markdown files with intelligent debounce.
///
/// NO save button — saves automatically when the user stops typing.
/// Uses an 800ms debounce to avoid saving on every keystroke.
/// Only persists to the local Drift database — remote sync is handled
/// separately on app open/close to avoid excessive Supabase calls.
class MarkdownAutoSaveService {
  final UpdateMarkdownFileUseCase _updateFile;

  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 800);

  /// Callback invoked after a successful save (can be async).
  Future<void> Function(String fileId)? onSaved;

  MarkdownAutoSaveService(this._updateFile);

  /// Schedule an auto-save for the given markdown file.
  /// Resets the debounce timer on each call.
  void scheduleAutoSave({
    required String fileId,
    String? title,
    String? content,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      await _performSave(fileId: fileId, title: title, content: content);
    });
  }

  /// Force an immediate save (e.g., when navigating away).
  Future<void> forceSave({
    required String fileId,
    String? title,
    String? content,
  }) async {
    _debounceTimer?.cancel();
    await _performSave(fileId: fileId, title: title, content: content);
  }

  Future<void> _performSave({
    required String fileId,
    String? title,
    String? content,
  }) async {
    final updated = await _updateFile.execute(
      fileId: fileId,
      title: title,
      content: content,
    );

    if (updated != null) {
      await onSaved?.call(fileId);
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
