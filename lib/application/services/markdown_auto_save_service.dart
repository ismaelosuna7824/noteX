import 'dart:async';

import '../use_cases/markdown/update_markdown_file_use_case.dart';

/// Application service: Auto-save for markdown files with dirty-flag + periodic timer.
///
/// NO save button — saves automatically when the user stops typing.
/// The editor is **100 % decoupled** from the save pipeline:
///
///  1. The page calls [watch] once when loading a file, registering lazy
///     getters for title & content.
///  2. On every keystroke the page calls [markDirty] — a single `bool`
///     assignment with **zero** overhead on the UI thread.
///  3. A periodic timer (every 3 s) checks the flag. If dirty it reads
///     the getters and persists to the local Drift database.
///
/// Only persists locally — remote sync is handled on app open/close.
class MarkdownAutoSaveService {
  final UpdateMarkdownFileUseCase _updateFile;

  // ── Periodic timer ───────────────────────────────────────────────────
  Timer? _periodicTimer;
  static const _checkInterval = Duration(seconds: 3);

  // ── Dirty-flag state ─────────────────────────────────────────────────
  bool _isDirty = false;
  String? _watchedFileId;
  String Function()? _getTitle;
  String Function()? _getContent;

  /// Callback invoked after a successful save (can be async).
  Future<void> Function(String fileId)? onSaved;

  MarkdownAutoSaveService(this._updateFile);

  // ── Public API ───────────────────────────────────────────────────────

  /// Register a file to watch for auto-saving.
  ///
  /// Call once when loading a file. The [getTitle] and [getContent] closures
  /// are only evaluated when the periodic timer detects unsaved changes —
  /// **never** on the keystroke itself.
  void watch({
    required String fileId,
    required String Function() getTitle,
    required String Function() getContent,
  }) {
    _watchedFileId = fileId;
    _getTitle = getTitle;
    _getContent = getContent;
    _isDirty = false;
    _startTimer();
  }

  /// Mark the current file as having unsaved changes.
  ///
  /// Cost: a single boolean assignment — zero overhead on the UI thread.
  void markDirty() {
    _isDirty = true;
  }

  /// Stop watching the current file (e.g., before disposing controllers).
  void unwatch() {
    _stopTimer();
    _watchedFileId = null;
    _getTitle = null;
    _getContent = null;
    _isDirty = false;
  }

  /// Force an immediate save (e.g., when navigating away or disposing).
  Future<void> forceSave({
    required String fileId,
    String? title,
    String? content,
  }) async {
    _isDirty = false;
    await _performSave(fileId: fileId, title: title, content: content);
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
    if (!_isDirty || _watchedFileId == null) return;
    _isDirty = false;

    final fileId = _watchedFileId!;
    _updateFile
        .execute(
          fileId: fileId,
          title: _getTitle?.call(),
          content: _getContent?.call(),
        )
        .whenComplete(() => onSaved?.call(fileId));
  }

  /// Force an immediate save (dispose / navigation).
  Future<void> _performSave({
    required String fileId,
    String? title,
    String? content,
  }) async {
    await _updateFile.execute(
      fileId: fileId,
      title: title,
      content: content,
    );
    await onSaved?.call(fileId);
  }
}
