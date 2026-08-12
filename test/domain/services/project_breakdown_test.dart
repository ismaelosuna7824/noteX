import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/project.dart';
import 'package:notex/domain/entities/time_entry.dart';
import 'package:notex/domain/services/project_breakdown.dart';

final _day = DateTime(2026, 8, 12);
DateTime _at(int hour, [int minute = 0]) =>
    DateTime(_day.year, _day.month, _day.day, hour, minute);

Project _project(String id, String name) => Project(
      id: id,
      name: name,
      colorValue: 0xFF6C5CE7,
      createdAt: _day,
      updatedAt: _day,
    );

TimeEntry _entry(String id, String? projectId, DateTime start, DateTime? end) =>
    TimeEntry(
      id: id,
      description: id,
      projectId: projectId,
      startTime: start,
      endTime: end,
      updatedAt: start,
    );

void main() {
  final atenas = _project('p1', 'Atenas');
  final esparta = _project('p2', 'Esparta');

  test('time is split per project and summed within one', () {
    final shares = breakdownByProject([
      _entry('a', 'p1', _at(9), _at(10)),
      _entry('b', 'p1', _at(14), _at(15)),
      _entry('c', 'p2', _at(11), _at(11, 30)),
    ], [
      atenas,
      esparta
    ]);

    expect(shares.map((s) => s.label), ['Atenas', 'Esparta']);
    expect(shares.first.total, const Duration(hours: 2));
    expect(shares.last.total, const Duration(minutes: 30));
  });

  test('fractions are shares of the period, and they add up', () {
    final shares = breakdownByProject([
      _entry('a', 'p1', _at(9), _at(12)),
      _entry('b', 'p2', _at(13), _at(14)),
    ], [
      atenas,
      esparta
    ]);

    expect(shares.first.fraction, closeTo(0.75, 1e-9));
    expect(shares.last.fraction, closeTo(0.25, 1e-9));
  });

  test('unassigned time is a row, not a silence', () {
    final shares = breakdownByProject([
      _entry('a', 'p1', _at(9), _at(10)),
      _entry('b', null, _at(11), _at(13)),
    ], [
      atenas
    ]);

    expect(shares.first.label, 'No project');
    expect(shares.first.total, const Duration(hours: 2));
  });

  test('a deleted project leaves its hours in the total', () {
    // Dropping orphans would shrink a total the user already read on screen.
    final shares = breakdownByProject([
      _entry('a', 'gone', _at(9), _at(10)),
    ], [
      atenas
    ]);

    expect(shares.single.label, 'No project');
    expect(shares.single.total, const Duration(hours: 1));
    expect(shares.single.fraction, 1);
  });

  test('a tie puts named work above unassigned time', () {
    final shares = breakdownByProject([
      _entry('a', 'p1', _at(9), _at(10)),
      _entry('b', null, _at(11), _at(12)),
    ], [
      atenas
    ]);

    expect(shares.map((s) => s.label), ['Atenas', 'No project']);
  });

  test('a running entry counts up to now', () {
    final shares = breakdownByProject(
      [_entry('a', 'p1', _at(9), null)],
      [atenas],
      now: _at(11),
    );

    expect(shares.single.total, const Duration(hours: 2));
  });

  test('a period of only zero-length entries does not produce NaN', () {
    final shares = breakdownByProject([
      _entry('a', 'p1', _at(9), _at(9)),
    ], [
      atenas
    ]);

    expect(shares.single.fraction, 0);
  });

  test('an empty period breaks down into nothing', () {
    expect(breakdownByProject([], [atenas]), isEmpty);
  });
}
