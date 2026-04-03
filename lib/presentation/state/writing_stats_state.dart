import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/note.dart';

/// Tracks writing activity: daily word counts, note counts, and streak.
///
/// Persists to `notex_writing_stats.json` so the streak survives app restarts.
class WritingStatsState extends ChangeNotifier {
  int _currentStreak = 0;
  String? _lastActiveDate; // "2026-04-01" format
  Map<String, int> _dailyWordCounts = {}; // date → word count
  Map<String, int> _dailyNoteCounts = {}; // date → note count

  int get currentStreak => _currentStreak;

  int get todayWordCount {
    final key = _dateKey(DateTime.now());
    return _dailyWordCounts[key] ?? 0;
  }

  int get yesterdayWordCount {
    final key = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    return _dailyWordCounts[key] ?? 0;
  }

  int get yesterdayNoteCount {
    final key = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    return _dailyNoteCounts[key] ?? 0;
  }

  /// Last 7 days of word counts (oldest first), for the mini chart.
  List<int> get weeklyWordCounts {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return _dailyWordCounts[_dateKey(day)] ?? 0;
    });
  }

  /// Last 7 day labels (e.g. "Mon", "Tue").
  List<String> get weeklyLabels {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return days[day.weekday - 1];
    });
  }

  /// Compute stats from the current notes list.
  /// Called on app open and after each save.
  void recordActivity(List<Note> notes) {
    final today = _dateKey(DateTime.now());

    // Compute today's stats from all notes created today
    final todayNotes = notes.where((n) =>
        !n.isEmpty && !n.isDeleted && n.isForDate(DateTime.now())).toList();
    final todayWords = notes
        .where((n) => !n.isEmpty && !n.isDeleted)
        .fold<int>(0, (sum, n) => sum + n.wordCount);

    // Update today's counts
    _dailyWordCounts[today] = todayWords;
    _dailyNoteCounts[today] = todayNotes.length;

    // Update streak
    if (_lastActiveDate == null) {
      // First time ever
      _currentStreak = todayNotes.isNotEmpty ? 1 : 0;
    } else if (_lastActiveDate == today) {
      // Already recorded today — just update counts
    } else {
      final yesterday = _dateKey(
          DateTime.now().subtract(const Duration(days: 1)));
      if (_lastActiveDate == yesterday) {
        // Consecutive day — increment streak
        _currentStreak++;
      } else {
        // Broke the streak — reset
        _currentStreak = 1;
      }
    }

    if (todayNotes.isNotEmpty) {
      _lastActiveDate = today;
    }

    // Prune old data (keep 14 days max)
    _pruneOldData();
    _saveToDisk();
    notifyListeners();
  }

  void _pruneOldData() {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final cutoffKey = _dateKey(cutoff);
    _dailyWordCounts.removeWhere((key, _) => key.compareTo(cutoffKey) < 0);
    _dailyNoteCounts.removeWhere((key, _) => key.compareTo(cutoffKey) < 0);
  }

  /// Load persisted stats from disk.
  Future<void> loadFromDisk() async {
    try {
      final file = await _getSettingsFile();
      if (!await file.exists()) return;

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _currentStreak = json['currentStreak'] as int? ?? 0;
      _lastActiveDate = json['lastActiveDate'] as String?;

      final wordCounts = json['dailyWordCounts'] as Map<String, dynamic>?;
      if (wordCounts != null) {
        _dailyWordCounts = wordCounts.map(
            (k, v) => MapEntry(k, v as int? ?? 0));
      }

      final noteCounts = json['dailyNoteCounts'] as Map<String, dynamic>?;
      if (noteCounts != null) {
        _dailyNoteCounts = noteCounts.map(
            (k, v) => MapEntry(k, v as int? ?? 0));
      }
    } catch (_) {
      // Keep defaults on corrupt file.
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getSettingsFile();
      await file.writeAsString(jsonEncode({
        'currentStreak': _currentStreak,
        'lastActiveDate': _lastActiveDate,
        'dailyWordCounts': _dailyWordCounts,
        'dailyNoteCounts': _dailyNoteCounts,
      }));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/notex_writing_stats.json');
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
