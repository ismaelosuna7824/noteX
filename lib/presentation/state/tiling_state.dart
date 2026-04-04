import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/note.dart';

/// Holds tiling layout state. Persisted to disk as JSON (note IDs only).
/// Registered as a singleton in GetIt so it survives tab changes.
class TilingState {
  static const int maxTiles = 4;

  final List<Note> tiledNotes = [];
  bool isActive = false;

  /// Notifies only the border widgets — no parent rebuilds.
  final ValueNotifier<String?> focusNotifier = ValueNotifier(null);

  String? get focusedNoteId => focusNotifier.value;
  set focusedNoteId(String? id) => focusNotifier.value = id;

  /// Guard: don't save while loading to prevent overwriting restored state.
  bool _isLoading = false;

  /// Save callbacks registered by each TilingEditorPanel.
  /// Called before exiting tiling to flush all edits to DB.
  final Map<String, Future<void> Function()> _panelSavers = {};

  void registerSaver(String noteId, Future<void> Function() saver) {
    _panelSavers[noteId] = saver;
  }

  void unregisterSaver(String noteId) {
    _panelSavers.remove(noteId);
  }

  /// Flush all panel edits to DB. Returns when all saves complete.
  Future<void> flushAll() async {
    // Copy values — savers may be modified during iteration
    final savers = List<Future<void> Function()>.from(_panelSavers.values);
    await Future.wait(savers.map((s) {
      try {
        return s();
      } catch (e) {
        return Future.value();
      }
    }));
  }

  int get tileCount => tiledNotes.length;
  bool get canAddTile => tiledNotes.length < maxTiles;

  /// Notes in insertion order (no reordering on focus change).
  List<Note> get orderedNotes => tiledNotes;

  void enterTiling({List<Note>? initialNotes}) {
    isActive = true;
    if (initialNotes != null) {
      tiledNotes.clear();
      tiledNotes.addAll(initialNotes.take(maxTiles));
      focusedNoteId = tiledNotes.isNotEmpty ? tiledNotes.first.id : null;
    }
    _saveToDisk();
  }

  void exitTiling() {
    isActive = false;
    tiledNotes.clear();
    focusedNoteId = null;
    _panelSavers.clear();
    _saveToDisk();
  }

  bool addNote(Note note) {
    if (tiledNotes.length >= maxTiles) return false;
    if (tiledNotes.any((n) => n.id == note.id)) return false;
    tiledNotes.add(note);
    focusedNoteId ??= note.id;
    if (!isActive) isActive = true;
    _saveToDisk();
    return true;
  }

  void removeNote(String noteId) {
    tiledNotes.removeWhere((n) => n.id == noteId);
    if (focusedNoteId == noteId) {
      focusedNoteId = tiledNotes.isNotEmpty ? tiledNotes.first.id : null;
    }
    // Auto-exit tiling when only 1 or 0 notes remain
    if (tiledNotes.length <= 1) isActive = false;
    _saveToDisk();
  }

  void setFocusedNote(String noteId) {
    if (focusedNoteId == noteId) return;
    if (tiledNotes.any((n) => n.id == noteId)) {
      focusedNoteId = noteId;
      _saveToDisk();
    }
  }

  bool containsNote(String noteId) =>
      tiledNotes.any((n) => n.id == noteId);

  // ── Persistence ────────────────────────────────────────────────────

  Future<void> loadFromDisk(List<Note> allNotes) async {
    _isLoading = true;
    try {
      final file = await _getSettingsFile();
      if (!await file.exists()) return;

      final raw = await file.readAsString();

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final noteIds = (json['noteIds'] as List<dynamic>?)?.cast<String>() ?? [];
      final savedFocusId = json['focusedNoteId'] as String?;
      final savedActive = json['isActive'] as bool? ?? false;

      if (!savedActive || noteIds.isEmpty) return;

      final noteMap = {for (final n in allNotes) n.id: n};
      final resolved = <Note>[];
      for (final id in noteIds) {
        final note = noteMap[id];
        if (note != null) resolved.add(note);
      }

      if (resolved.isEmpty) return;

      tiledNotes.clear();
      tiledNotes.addAll(resolved);
      focusedNoteId = (savedFocusId != null && noteMap.containsKey(savedFocusId))
          ? savedFocusId
          : resolved.first.id;
      isActive = true;
    } catch (_) {
      // Corrupted file — ignore
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _saveToDisk() async {
    if (_isLoading) return;
    final data = {
      'isActive': isActive,
      'noteIds': tiledNotes.map((n) => n.id).toList(),
      'focusedNoteId': focusedNoteId,
    };
    final file = await _getSettingsFile();
    await file.writeAsString(jsonEncode(data));
  }

  static Future<File> _getSettingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/notex_tiling_settings.json');
  }
}
