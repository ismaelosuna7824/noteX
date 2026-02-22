import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/project.dart';
import '../../domain/entities/time_entry.dart';
import '../../application/use_cases/timer/create_project_use_case.dart';
import '../../application/use_cases/timer/get_projects_use_case.dart';
import '../../application/use_cases/timer/delete_project_use_case.dart';
import '../../application/use_cases/timer/start_timer_use_case.dart';
import '../../application/use_cases/timer/stop_timer_use_case.dart';
import '../../application/use_cases/timer/get_time_entries_use_case.dart';
import '../../application/use_cases/timer/delete_time_entry_use_case.dart';
import '../../application/use_cases/timer/update_time_entry_use_case.dart';

/// Central state for the time tracking feature.
///
/// Owns the live [Timer] ticker — must be registered as a GetIt singleton.
class TimerState extends ChangeNotifier {
  final CreateProjectUseCase _createProject;
  final GetProjectsUseCase _getProjects;
  final DeleteProjectUseCase _deleteProject;
  final StartTimerUseCase _startTimer;
  final StopTimerUseCase _stopTimer;
  final GetTimeEntriesUseCase _getEntries;
  final DeleteTimeEntryUseCase _deleteEntry;
  final UpdateTimeEntryUseCase _updateEntry;

  // ── Data ─────────────────────────────────────────────────────────────────
  TimeEntry? _runningEntry;
  List<TimeEntry> _weekEntries = [];
  List<Project> _projects = [];

  // ── Week navigation ───────────────────────────────────────────────────────
  DateTime _weekStart = _currentWeekMonday();

  // ── Draft input (timer bar) ───────────────────────────────────────────────
  String _draftDescription = '';
  String? _draftProjectId;

  // ── Misc ─────────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _isInitialized = false;
  Timer? _ticker;

  TimerState({
    required CreateProjectUseCase createProject,
    required GetProjectsUseCase getProjects,
    required DeleteProjectUseCase deleteProject,
    required StartTimerUseCase startTimer,
    required StopTimerUseCase stopTimer,
    required GetTimeEntriesUseCase getEntries,
    required DeleteTimeEntryUseCase deleteEntry,
    required UpdateTimeEntryUseCase updateEntry,
  })  : _createProject = createProject,
        _getProjects = getProjects,
        _deleteProject = deleteProject,
        _startTimer = startTimer,
        _stopTimer = stopTimer,
        _getEntries = getEntries,
        _deleteEntry = deleteEntry,
        _updateEntry = updateEntry;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  bool get isRunning => _runningEntry != null;
  TimeEntry? get runningEntry => _runningEntry;
  List<Project> get projects => _projects;
  List<TimeEntry> get weekEntries => _weekEntries;
  DateTime get weekStart => _weekStart;
  DateTime get weekEnd => _weekStart.add(const Duration(days: 7));
  String get draftDescription => _draftDescription;
  String? get draftProjectId => _draftProjectId;

  /// ISO 8601 week number for [_weekStart].
  int get weekNumber {
    final jan4 = DateTime(_weekStart.year, 1, 4);
    final startOfWeek1 =
        jan4.subtract(Duration(days: jan4.weekday - 1));
    final diff = _weekStart.difference(startOfWeek1).inDays;
    return (diff / 7).floor() + 1;
  }

  /// True when the displayed week is the current calendar week.
  bool get isCurrentWeek {
    final now = _currentWeekMonday();
    return _weekStart.year == now.year &&
        _weekStart.month == now.month &&
        _weekStart.day == now.day;
  }

  /// Live elapsed duration of the running entry (recomputed via DateTime.now()).
  Duration get liveElapsed => _runningEntry?.elapsed ?? Duration.zero;

  /// Total duration for all entries in the current week.
  Duration get weekTotal => _weekEntries.fold(
        Duration.zero,
        (acc, e) => acc + e.elapsed,
      );

  /// Entries grouped by calendar date (midnight), newest date first.
  Map<DateTime, List<TimeEntry>> get entriesByDay {
    final map = <DateTime, List<TimeEntry>>{};
    for (final entry in _weekEntries) {
      final day = DateTime(
        entry.startTime.year,
        entry.startTime.month,
        entry.startTime.day,
      );
      map.putIfAbsent(day, () => []).add(entry);
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
  }

  /// Total duration for entries on [date].
  Duration dailyTotal(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return (entriesByDay[day] ?? []).fold(
      Duration.zero,
      (acc, e) => acc + e.elapsed,
    );
  }

  /// Look up a project by id (returns null for "No Project" entries).
  Project? projectForId(String? id) {
    if (id == null) return null;
    return _projects.cast<Project?>().firstWhere(
          (p) => p?.id == id,
          orElse: () => null,
        );
  }

  // ── Initialization ────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialized) {
      try {
        _projects = await _getProjects.getAll();
        _runningEntry = await _getEntries.getRunning();
        await _loadWeekEntries();
      } catch (e) {
        // ignore: avoid_print
        print('[TimerState] refresh error: $e');
      } finally {
        Future.microtask(notifyListeners);
      }
      return;
    }

    _isLoading = true;
    Future.microtask(notifyListeners);

    try {
      _projects = await _getProjects.getAll();
      _runningEntry = await _getEntries.getRunning();
      await _loadWeekEntries();
      if (_runningEntry != null) _startTicker();
      _isInitialized = true;
    } catch (e) {
      // ignore: avoid_print
      print('[TimerState] initialize error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Timer control ─────────────────────────────────────────────────────────

  Future<void> startTimer() async {
    _runningEntry = await _startTimer.execute(
      id: const Uuid().v4(),
      description: _draftDescription,
      projectId: _draftProjectId,
    );
    _draftDescription = '';
    // Keep _draftProjectId so the next entry defaults to the same project.
    await _loadWeekEntries();
    _startTicker();
    notifyListeners();
  }

  Future<void> stopTimer() async {
    if (_runningEntry == null) return;
    await _stopTimer.execute(_runningEntry!.id);
    _stopTicker();
    _runningEntry = null;
    await _loadWeekEntries();
    notifyListeners();
  }

  // ── Draft inputs ──────────────────────────────────────────────────────────

  void setDraftDescription(String value) {
    _draftDescription = value;
    notifyListeners();
  }

  void setDraftProject(String? projectId) {
    _draftProjectId = projectId;
    notifyListeners();
  }

  // ── Week navigation ───────────────────────────────────────────────────────

  Future<void> goToPreviousWeek() async {
    _weekStart = _weekStart.subtract(const Duration(days: 7));
    await _loadWeekEntries();
    notifyListeners();
  }

  Future<void> goToNextWeek() async {
    _weekStart = _weekStart.add(const Duration(days: 7));
    await _loadWeekEntries();
    notifyListeners();
  }

  Future<void> goToCurrentWeek() async {
    _weekStart = _currentWeekMonday();
    await _loadWeekEntries();
    notifyListeners();
  }

  /// Directly jump to the week containing [monday].
  Future<void> goToWeek(DateTime monday) async {
    _weekStart = DateTime(monday.year, monday.month, monday.day);
    await _loadWeekEntries();
    notifyListeners();
  }

  // ── Entry management ──────────────────────────────────────────────────────

  Future<void> deleteEntry(String entryId) async {
    await _deleteEntry.execute(entryId);
    if (_runningEntry?.id == entryId) {
      _stopTicker();
      _runningEntry = null;
    }
    await _loadWeekEntries();
    notifyListeners();
  }

  Future<void> updateEntry({
    required String entryId,
    String? description,
    Object? projectId = const _Unset(),
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final updated = await _updateEntry.execute(
      entryId: entryId,
      description: description,
      projectId: projectId,
      startTime: startTime,
      endTime: endTime,
    );
    if (updated != null && _runningEntry?.id == entryId) {
      _runningEntry = updated;
    }
    await _loadWeekEntries();
    notifyListeners();
  }

  // ── Project management ────────────────────────────────────────────────────

  Future<Project> createProject({
    required String name,
    required int colorValue,
  }) async {
    final p = await _createProject.execute(
      id: const Uuid().v4(),
      name: name,
      colorValue: colorValue,
    );
    _projects = await _getProjects.getAll();
    notifyListeners();
    return p;
  }

  Future<void> deleteProject(String projectId) async {
    await _deleteProject.execute(projectId);
    _projects = await _getProjects.getAll();
    if (_draftProjectId == projectId) _draftProjectId = null;
    notifyListeners();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _loadWeekEntries() async {
    _weekEntries = await _getEntries.getByDateRange(weekStart, weekEnd);
    // If there is a running entry, ensure it appears in the list
    // even if its startTime predates the current week view.
    if (_runningEntry != null) {
      final alreadyIn = _weekEntries.any((e) => e.id == _runningEntry!.id);
      if (!alreadyIn) {
        _weekEntries = [_runningEntry!, ..._weekEntries];
      }
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  static DateTime _currentWeekMonday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}

// Sentinel to distinguish "not provided" from explicit null in updateEntry.
class _Unset {
  const _Unset();
}
