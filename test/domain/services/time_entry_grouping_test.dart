import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/time_entry.dart';
import 'package:notex/domain/services/time_entry_grouping.dart';

TimeEntry _entry({
  required String id,
  required String description,
  String? projectId,
  required DateTime start,
  DateTime? end,
  String? taskId,
}) =>
    TimeEntry(
      id: id,
      description: description,
      projectId: projectId,
      startTime: start,
      endTime: end,
      updatedAt: start,
      taskId: taskId,
    );

final _day = DateTime(2026, 8, 12);
DateTime _at(int hour, [int minute = 0]) =>
    DateTime(_day.year, _day.month, _day.day, hour, minute);

void main() {
  test('the same work started twice becomes one row', () {
    final groups = groupTimeEntries([
      _entry(id: 'b', description: 'Daily', start: _at(14), end: _at(14, 20)),
      _entry(id: 'a', description: 'Daily', start: _at(9), end: _at(9, 40)),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.entries, hasLength(2));
    expect(groups.single.isSingle, isFalse);
  });

  test('the total is summed, not measured end to end', () {
    // Two half-hour runs either side of lunch are an hour of work, not five.
    final groups = groupTimeEntries([
      _entry(id: 'b', description: 'Deep work', start: _at(14), end: _at(14, 30)),
      _entry(id: 'a', description: 'Deep work', start: _at(9), end: _at(9, 30)),
    ]);

    expect(groups.single.totalAt(_at(18)), const Duration(hours: 1));
    expect(groups.single.earliestStart, _at(9));
    expect(groups.single.latestEnd, _at(14, 30));
  });

  test('the same word under two projects stays two rows', () {
    // Merging them would report a client's time against another client.
    final groups = groupTimeEntries([
      _entry(id: 'a', description: 'Daily', projectId: 'p1', start: _at(9), end: _at(9, 10)),
      _entry(id: 'b', description: 'Daily', projectId: 'p2', start: _at(10), end: _at(10, 10)),
    ]);

    expect(groups, hasLength(2));
  });

  test('casing and stray spaces do not split a task in half', () {
    final groups = groupTimeEntries([
      _entry(id: 'a', description: 'Daily', start: _at(9), end: _at(9, 10)),
      _entry(id: 'b', description: ' daily ', start: _at(10), end: _at(10, 10)),
    ]);

    expect(groups, hasLength(1),
        reason: 'a hurried lowercase entry is the same task');
  });

  test('a single run is not dressed up as a group', () {
    final groups = groupTimeEntries([
      _entry(id: 'a', description: 'One off', start: _at(9), end: _at(9, 10)),
    ]);

    expect(groups.single.isSingle, isTrue);
  });

  test('a running entry keeps counting inside its group', () {
    final groups = groupTimeEntries([
      _entry(id: 'b', description: 'Daily', start: _at(14)),
      _entry(id: 'a', description: 'Daily', start: _at(9), end: _at(9, 30)),
    ]);

    expect(groups.single.hasRunning, isTrue);
    // 30 minutes finished, plus an hour still running at 15:00.
    expect(groups.single.totalAt(_at(15)), const Duration(minutes: 90));
    expect(groups.single.latestEnd, isNull,
        reason: 'a group that is still running has no end yet');
  });

  test('groups appear where their most recent run appeared', () {
    // A list read top-down yesterday should read the same way today.
    final groups = groupTimeEntries([
      _entry(id: 'c', description: 'Second', start: _at(15), end: _at(15, 5)),
      _entry(id: 'b', description: 'First', start: _at(14), end: _at(14, 5)),
      _entry(id: 'a', description: 'First', start: _at(9), end: _at(9, 5)),
    ]);

    expect(groups.map((g) => g.description), ['Second', 'First']);
  });

  test('an empty list groups into nothing', () {
    expect(groupTimeEntries([]), isEmpty);
  });

  test('a group exposes the taskId of whichever of its runs carries one',
      () {
    final groups = groupTimeEntries([
      _entry(
        id: 'b',
        description: 'Daily',
        start: _at(14),
        end: _at(14, 20),
        taskId: 'task-1',
      ),
      _entry(id: 'a', description: 'Daily', start: _at(9), end: _at(9, 40)),
    ]);

    expect(groups.single.taskId, 'task-1');
  });

  test('a group with no task-linked run exposes a null taskId', () {
    final groups = groupTimeEntries([
      _entry(id: 'a', description: 'Free text', start: _at(9), end: _at(9, 10)),
    ]);

    expect(groups.single.taskId, isNull);
  });
}
