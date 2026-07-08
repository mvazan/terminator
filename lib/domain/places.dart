/// Ordered-vs-filled places math.
///
/// Ordering happens outside the app; the app records which starts and how
/// many *lanes* were taken. The number of player places on a start is
/// lanes × kind.playersPerLane — the same as lanes for most kinds, but double
/// for tandem (2 players share one lane). Player places may exceed the players
/// currently known (someone is found later or plays twice) and may stay empty.
library;

import 'models.dart';

class SlotPlaces {
  const SlotPlaces({
    required this.slot,
    required this.lanes,
    required this.capacity,
    required this.filled,
  });

  final Slot slot;

  /// Lanes ordered for this start (the count entered when recording).
  final int lanes;

  /// Player places = lanes × kind.playersPerLane (tandem: 2 per lane).
  final int capacity;

  final int filled;

  int get free => capacity - filled;

  bool get hasFreePlace => free > 0;
}

class OrderPlaces {
  const OrderPlaces({required this.perSlot});

  final List<SlotPlaces> perSlot;

  /// Total lanes ordered across the slots of the order.
  int get orderedLanes => perSlot.fold(0, (sum, s) => sum + s.lanes);

  /// Total player places across the slots (tandem-doubled where applicable).
  int get orderedPlaces => perSlot.fold(0, (sum, s) => sum + s.capacity);

  int get filledPlaces => perSlot.fold(0, (sum, s) => sum + s.filled);

  int get freePlaces => orderedPlaces - filledPlaces;
}

/// Computes places for the slots of one order. [lanesBySlot] holds the lane
/// counts entered when the order was recorded (null/missing = 1 lane).
OrderPlaces orderPlaces({
  required Tournament tournament,
  required List<Slot> orderSlots,
  required List<RosterEntry> rosters,
  Map<String, int?> lanesBySlot = const {},
}) {
  final filledBySlot = <String, int>{};
  for (final r in rosters) {
    filledBySlot[r.slotId] = (filledBySlot[r.slotId] ?? 0) + 1;
  }
  final perLane = tournament.kind.playersPerLane;
  final sorted = [...orderSlots]..sort(Slot.compare);
  return OrderPlaces(perSlot: [
    for (final slot in sorted)
      () {
        final lanes = lanesBySlot[slot.id] ?? 1;
        return SlotPlaces(
          slot: slot,
          lanes: lanes,
          capacity: lanes * perLane,
          filled: filledBySlot[slot.id] ?? 0,
        );
      }(),
  ]);
}
