/// A single (date, time) slot specification, produced by the day-group
/// pattern generator in day_groups.dart or imported by the web scraper.
library;

import 'models.dart';

class SlotSpec {
  const SlotSpec(this.date, this.time);

  final Day date;
  final HourMinute time;

  @override
  bool operator ==(Object other) =>
      other is SlotSpec && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => '$date $time';
}
