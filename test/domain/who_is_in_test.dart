import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/heatmap.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/domain/who_is_in.dart';

import 'helpers.dart';

void main() {
  const t10 = HourMinute(10, 0);
  const t12 = HourMinute(12, 0);
  const t15 = HourMinute(15, 0);
  const t17 = HourMinute(17, 0);
  const t19 = HourMinute(19, 0);
  final times = [t10, t12, t15, t17, t19];

  group('summarizeTimes', () {
    test('all ticked -> celý den', () {
      expect(summarizeTimes(times, {...times}), 'celý den');
    });

    test('contiguous suffix -> od X (first ticked)', () {
      expect(summarizeTimes(times, {t15, t17, t19}), 'od 15:00');
    });

    test('contiguous prefix -> do X (last ticked)', () {
      expect(summarizeTimes(times, {t10, t12, t15}), 'do 15:00');
    });

    test('contiguous middle run -> X–Y', () {
      expect(summarizeTimes(times, {t12, t15}), '12:00–15:00');
    });

    test('single middle tick -> just the time', () {
      expect(summarizeTimes(times, {t15}), '15:00');
    });

    test('non-contiguous -> listed times', () {
      expect(summarizeTimes(times, {t10, t15, t19}), '10:00, 15:00, 19:00');
    });

    test('one-slot day, ticked -> celý den', () {
      expect(summarizeTimes([t15], {t15}), 'celý den');
    });
  });

  test('summarizeDayByUser groups per person from slot stats', () {
    final day = Day(2026, 4, 23);
    final s1 = makeSlot('s1', day, t15);
    final s2 = makeSlot('s2', day, t17);
    final s3 = makeSlot('s3', day, t19);
    final stats = {
      's1': SlotStats(
          slot: s1, count: 1, isOrderable: false, userIds: const {'pavel'}),
      's2': SlotStats(
          slot: s2,
          count: 2,
          isOrderable: false,
          userIds: const {'pavel', 'milos'}),
      's3': SlotStats(
          slot: s3,
          count: 2,
          isOrderable: false,
          userIds: const {'pavel', 'milos'}),
    };

    final byUser = summarizeDayByUser(daySlots: [s1, s2, s3], statsBySlotId: stats);
    expect(byUser['pavel'], 'celý den');
    expect(byUser['milos'], 'od 17:00');
    expect(byUser.length, 2);
  });
}
