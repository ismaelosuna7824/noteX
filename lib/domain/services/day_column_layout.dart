import '../entities/time_entry.dart';

/// Where one entry sits inside a day column.
class PlacedEntry {
  const PlacedEntry({
    required this.entry,
    required this.column,
    required this.columns,
  });

  final TimeEntry entry;

  /// Which lane this entry occupies, from the left.
  final int column;

  /// How many lanes its cluster was split into. Width is `1 / columns`.
  final int columns;
}

/// Places a day's entries side by side so none of them hides another.
///
/// Overlap is the normal case, not the exception: a timer left running while
/// another is started, or two manual entries recalled from memory, will cover
/// the same minutes. Drawn full-width in start order, the later one simply
/// paints over the earlier and a whole session disappears from the day.
///
/// Entries are split into clusters of transitively overlapping work, and only
/// within a cluster is the width divided. Splitting the whole day by its worst
/// moment would leave every entry a sliver because two of them once collided.
List<PlacedEntry> layoutDayColumn(List<TimeEntry> entries, DateTime now) {
  if (entries.isEmpty) return const [];

  DateTime endOf(TimeEntry entry) => entry.endTime ?? now;

  final sorted = [...entries]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final placed = <PlacedEntry>[];
  var cluster = <TimeEntry>[];
  DateTime? clusterEnd;

  void flush() {
    if (cluster.isEmpty) return;

    // Lowest free lane, which keeps entries as far left as they can go and
    // stops a cluster from growing lanes it does not need.
    final laneEnds = <DateTime>[];
    final lanes = <TimeEntry, int>{};

    for (final entry in cluster) {
      var lane = laneEnds.indexWhere(
        (end) => !end.isAfter(entry.startTime),
      );
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(endOf(entry));
      } else {
        laneEnds[lane] = endOf(entry);
      }
      lanes[entry] = lane;
    }

    for (final entry in cluster) {
      placed.add(PlacedEntry(
        entry: entry,
        column: lanes[entry]!,
        columns: laneEnds.length,
      ));
    }

    cluster = [];
    clusterEnd = null;
  }

  for (final entry in sorted) {
    // A new cluster begins where nothing before it is still open.
    if (clusterEnd != null && !entry.startTime.isBefore(clusterEnd!)) {
      flush();
    }

    cluster.add(entry);
    final end = endOf(entry);
    if (clusterEnd == null || end.isAfter(clusterEnd!)) clusterEnd = end;
  }
  flush();

  return placed;
}
