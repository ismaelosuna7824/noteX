import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/time_entry.dart';
import 'package:notex/domain/services/day_column_layout.dart';

final _day = DateTime(2026, 8, 12);
DateTime _at(int hour, [int minute = 0]) =>
    DateTime(_day.year, _day.month, _day.day, hour, minute);

TimeEntry _entry(String id, DateTime start, DateTime? end) => TimeEntry(
      id: id,
      description: id,
      startTime: start,
      endTime: end,
      updatedAt: start,
    );

PlacedEntry _find(List<PlacedEntry> placed, String id) =>
    placed.firstWhere((p) => p.entry.id == id);

void main() {
  final now = _at(23);

  test('a day without overlap keeps the full width', () {
    final placed = layoutDayColumn([
      _entry('a', _at(9), _at(10)),
      _entry('b', _at(11), _at(12)),
    ], now);

    for (final p in placed) {
      expect(p.columns, 1);
      expect(p.column, 0);
    }
  });

  test('two overlapping entries split the width, and neither is hidden', () {
    // Drawn full width in start order, the later one paints over the earlier
    // and a whole session vanishes from the day.
    final placed = layoutDayColumn([
      _entry('a', _at(9), _at(11)),
      _entry('b', _at(10), _at(12)),
    ], now);

    expect(placed.every((p) => p.columns == 2), isTrue);
    expect({_find(placed, 'a').column, _find(placed, 'b').column}, {0, 1});
  });

  test('a collision does not narrow the rest of the day', () {
    // Splitting the whole day by its worst moment would leave every entry a
    // sliver because two of them once collided.
    final placed = layoutDayColumn([
      _entry('a', _at(9), _at(11)),
      _entry('b', _at(10), _at(12)),
      _entry('lonely', _at(15), _at(16)),
    ], now);

    expect(_find(placed, 'lonely').columns, 1);
  });

  test('a lane is reused once it is free', () {
    // a and b overlap; c starts after a ends, so it belongs in a's lane
    // rather than opening a third.
    final placed = layoutDayColumn([
      _entry('a', _at(9), _at(10)),
      _entry('b', _at(9, 30), _at(12)),
      _entry('c', _at(10), _at(11)),
    ], now);

    expect(placed.every((p) => p.columns == 2), isTrue,
        reason: 'three overlapping-ish entries still need only two lanes');
    expect(_find(placed, 'c').column, _find(placed, 'a').column);
  });

  test('entries that merely touch are not overlapping', () {
    // 09:00-10:00 and 10:00-11:00 share an instant, not a minute of work.
    final placed = layoutDayColumn([
      _entry('a', _at(9), _at(10)),
      _entry('b', _at(10), _at(11)),
    ], now);

    expect(placed.every((p) => p.columns == 1), isTrue);
  });

  test('a running entry is laid out as if it ended now', () {
    final placed = layoutDayColumn([
      _entry('running', _at(9), null),
      _entry('later', _at(10), _at(11)),
    ], _at(12));

    expect(placed.every((p) => p.columns == 2), isTrue,
        reason: 'a running entry still occupies the time it has used');
  });

  test('an empty day places nothing', () {
    expect(layoutDayColumn([], now), isEmpty);
  });
}
