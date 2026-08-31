/// Chronologické řazení objednávek pro detail turnaje.
library;

import 'models.dart';

/// Kopie [orders] seřazená podle nejdřívějšího objednaného startu
/// (datum, čas přes [compareDayTime]); objednávky bez rozpoznatelných slotů
/// až nakonec. Shodný první start → starší `createdAt` dřív. Provider dává
/// newest-first (pro jiné obrazovky) — detail chce program turnaje.
List<Order> ordersByFirstStart(
  List<Order> orders, {
  required Map<String, Map<String, int>> orderSlots,
  required Map<String, Slot> slotById,
}) {
  Slot? firstSlot(Order o) {
    Slot? first;
    for (final slotId in (orderSlots[o.id] ?? const <String, int>{}).keys) {
      final slot = slotById[slotId];
      if (slot == null) continue;
      if (first == null ||
          compareDayTime(slot.date, slot.time, first.date, first.time) < 0) {
        first = slot;
      }
    }
    return first;
  }

  final firstByOrder = {for (final o in orders) o.id: firstSlot(o)};
  return List.of(orders)
    ..sort((a, b) {
      final fa = firstByOrder[a.id];
      final fb = firstByOrder[b.id];
      if (fa != null && fb != null) {
        final byStart = compareDayTime(fa.date, fa.time, fb.date, fb.time);
        if (byStart != 0) return byStart;
      } else if (fa != null || fb != null) {
        return fa == null ? 1 : -1; // bez slotů až za rozpoznané
      }
      return a.createdAt.compareTo(b.createdAt);
    });
}
