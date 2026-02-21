/// A single time-tracked work session.
///
/// When [endTime] is null, the entry is currently running.
class TimeEntry {
  final String id;
  final String description;
  final String? projectId; // null = "No Project"
  final DateTime startTime;
  final DateTime? endTime; // null = currently running

  const TimeEntry({
    required this.id,
    required this.description,
    required this.startTime,
    this.projectId,
    this.endTime,
  });

  /// True when this entry has no end time (the timer is live).
  bool get isRunning => endTime == null;

  /// Elapsed duration. If running, measures against [DateTime.now()].
  Duration get elapsed =>
      (endTime ?? DateTime.now()).difference(startTime);

  /// Returns a stopped copy with [endTime] set to now.
  TimeEntry stop() {
    return TimeEntry(
      id: id,
      description: description,
      projectId: projectId,
      startTime: startTime,
      endTime: DateTime.now(),
    );
  }

  TimeEntry copyWith({
    String? description,
    Object? projectId = const _Unset(),
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return TimeEntry(
      id: id,
      description: description ?? this.description,
      projectId: projectId is _Unset ? this.projectId : projectId as String?,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TimeEntry && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TimeEntry(id: $id, desc: $description, running: $isRunning)';
}

// Private sentinel for nullable copyWith fields.
class _Unset {
  const _Unset();
}
