/// Ordered-vs-filled places math.
///
/// Ordering happens outside the app; the app records which starts and how
/// many places were taken. Ordered places may exceed the players currently
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

  /// Places ordered for this start = tournament.maxPlayers (per-start size,
  /// e.g. 2 for dvojice). Null when the tournament has no fixed size.
  final int? capacity;

  final int filled;

  int? get free => capacity == null ? null : (capacity! - filled);

  bool get hasFreePlace => free == null || free! > 0;
}

class OrderPlaces {
  const OrderPlaces({required this.perSlot});

  final List<SlotPlaces> perSlot;

  int? get orderedPlaces {
    var total = 0;
    for (final s in perSlot) {
      if (s.capacity == null) return null;
      total += s.capacity!;
    }
    return total;
  }

  int get filledPlaces => perSlot.fold(0, (sum, s) => sum + s.filled);

  int? get freePlaces =>
      orderedPlaces == null ? null : orderedPlaces! - filledPlaces;
}

/// Computes places for the slots of one order.
OrderPlaces orderPlaces({
  required Tournament tournament,
  required List<Slot> orderSlots,
  required List<RosterEntry> rosters,
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
        capacity: tournament.maxPlayers,
        filled: filledBySlot[slot.id] ?? 0,
      ),
  ]);
}
