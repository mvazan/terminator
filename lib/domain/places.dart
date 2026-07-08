/// Ordered-vs-filled places math.
///
/// Ordering happens outside the app; the app records which starts and how
/// many places were taken. Capacity per start comes from the tournament
/// kind (dvojice = 2, …). Ordered places may exceed the players currently
/// known (5 players in a dvojice tournament → order 6 places; someone is
/// found later or plays twice), and places may stay empty.
library;

import 'models.dart';

class SlotPlaces {
  const SlotPlaces({
    required this.slot,
    required this.capacity,
    required this.filled,
  });

  final Slot slot;

  /// Places ordered for this start: the count entered when recording the
  /// order, falling back to tournament.kind.laneCapacity.
  final int capacity;

  final int filled;

  int get free => capacity - filled;

  bool get hasFreePlace => free > 0;
}

class OrderPlaces {
  const OrderPlaces({required this.perSlot});

  final List<SlotPlaces> perSlot;

  int get orderedPlaces => perSlot.fold(0, (sum, s) => sum + s.capacity);

  int get filledPlaces => perSlot.fold(0, (sum, s) => sum + s.filled);

  int get freePlaces => orderedPlaces - filledPlaces;
}

/// Computes places for the slots of one order. [placesBySlot] holds the
/// counts entered when the order was recorded (null/missing = kind default).
OrderPlaces orderPlaces({
  required Tournament tournament,
  required List<Slot> orderSlots,
  required List<RosterEntry> rosters,
  Map<String, int?> placesBySlot = const {},
}) {
  final filledBySlot = <String, int>{};
  for (final r in rosters) {
    filledBySlot[r.slotId] = (filledBySlot[r.slotId] ?? 0) + 1;
  }
  final sorted = [...orderSlots]..sort(Slot.compare);
  return OrderPlaces(perSlot: [
    for (final slot in sorted)
      SlotPlaces(
        slot: slot,
        capacity: placesBySlot[slot.id] ?? tournament.kind.laneCapacity,
        filled: filledBySlot[slot.id] ?? 0,
      ),
  ]);
}
