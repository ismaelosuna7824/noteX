import '../entities/project.dart';
import '../entities/time_entry.dart';

/// How much of a period went to one project.
class ProjectShare {
  const ProjectShare({
    required this.project,
    required this.total,
    required this.fraction,
  });

  /// The project, or null for time logged without one.
  final Project? project;

  final Duration total;

  /// This project's part of the period, 0..1.
  final double fraction;

  String get label => project?.name ?? 'No project';
}

/// Splits a period's entries by project, largest first.
///
/// A week total answers "did I work"; it cannot answer "on what". Fifty hours
/// is a different week depending on whether three of them were unassigned or
/// forty-seven were.
///
/// Entries pointing at a project that no longer exists are counted as
/// unassigned rather than dropped. Deleting a project must not quietly shrink
/// the total the user already saw.
List<ProjectShare> breakdownByProject(
  List<TimeEntry> entries,
  List<Project> projects, {
  DateTime? now,
}) {
  if (entries.isEmpty) return const [];

  final byId = {for (final project in projects) project.id: project};

  final totals = <String?, Duration>{};
  for (final entry in entries) {
    final key = byId.containsKey(entry.projectId) ? entry.projectId : null;
    final elapsed = now == null
        ? entry.elapsed
        : (entry.endTime ?? now).difference(entry.startTime);
    totals[key] = (totals[key] ?? Duration.zero) + elapsed;
  }

  final grand = totals.values.fold(Duration.zero, (acc, d) => acc + d);

  final shares = totals.entries
      .map((e) => ProjectShare(
            project: e.key == null ? null : byId[e.key],
            total: e.value,
            // A week of nothing but running entries started this second is all
            // zeroes; dividing there would hand every bar a NaN width.
            fraction: grand == Duration.zero
                ? 0
                : e.value.inMilliseconds / grand.inMilliseconds,
          ))
      .toList();

  shares.sort((a, b) {
    final byTotal = b.total.compareTo(a.total);
    if (byTotal != 0) return byTotal;
    // Named work outranks unassigned time when they tie, so the row a user can
    // act on is the one they read first.
    if (a.project == null) return 1;
    if (b.project == null) return -1;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });

  return shares;
}
