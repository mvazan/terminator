import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/domain/order_sort.dart';

Order _order(String id, DateTime createdAt) => Order(
      id: id,
      tournamentId: 't1',
      createdBy: 'u1',
      status: OrderStatus.ordered,
      note: '',
      createdAt: createdAt,
    );

Slot _slot(String id, Day date, HourMinute time) => Slot(
      id: id,
      tournamentId: 't1',
      date: date,
      time: time,
    );

void main() {
  final createdEarly = DateTime.utc(2026, 8, 1, 10);
  final createdLate = DateTime.utc(2026, 8, 20, 10);

  final slotById = {
    'sSat10': _slot('sSat10', Day(2026, 9, 5), const HourMinute(10, 0)),
    'sSat14': _slot('sSat14', Day(2026, 9, 5), const HourMinute(14, 0)),
    'sFri18': _slot('sFri18', Day(2026, 9, 4), const HourMinute(18, 0)),
  };

  test('řadí podle nejdřívějšího objednaného startu (datum i čas)', () {
    final orders = [
      _order('sobota-odpoledne', createdEarly),
      _order('patek', createdEarly),
      _order('sobota-rano', createdEarly),
    ];
    final orderSlots = {
      'sobota-odpoledne': {'sSat14': 1},
      'patek': {'sFri18': 1},
      // Víc slotů: počítá se ten nejdřívější.
      'sobota-rano': {'sSat14': 1, 'sSat10': 1},
    };
    final sorted = ordersByFirstStart(orders,
        orderSlots: orderSlots, slotById: slotById);
    expect([for (final o in sorted) o.id],
        ['patek', 'sobota-rano', 'sobota-odpoledne']);
  });

  test('newest-first vstup z provideru se přepíše na chronologii', () {
    final orders = [
      _order('pozdejsi', createdLate),
      _order('drivejsi', createdEarly),
    ];
    final orderSlots = {
      'pozdejsi': {'sSat10': 1},
      'drivejsi': {'sFri18': 1},
    };
    final sorted = ordersByFirstStart(orders,
        orderSlots: orderSlots, slotById: slotById);
    expect([for (final o in sorted) o.id], ['drivejsi', 'pozdejsi']);
  });

  test('bez rozpoznatelných slotů nakonec; shoda startu → starší dřív', () {
    final orders = [
      _order('bez-slotu', createdEarly),
      _order('stejny-start-novejsi', createdLate),
      _order('stejny-start-starsi', createdEarly),
    ];
    final orderSlots = {
      'bez-slotu': <String, int>{'neznamy-slot': 1},
      'stejny-start-novejsi': {'sSat10': 1},
      'stejny-start-starsi': {'sSat10': 1},
    };
    final sorted = ordersByFirstStart(orders,
        orderSlots: orderSlots, slotById: slotById);
    expect([for (final o in sorted) o.id],
        ['stejny-start-starsi', 'stejny-start-novejsi', 'bez-slotu']);
  });

  test('vstupní seznam nemutuje', () {
    final orders = [
      _order('b', createdLate),
      _order('a', createdEarly),
    ];
    final sorted = ordersByFirstStart(orders,
        orderSlots: const {}, slotById: slotById);
    expect([for (final o in orders) o.id], ['b', 'a']);
    expect([for (final o in sorted) o.id], ['a', 'b']);
  });
}
