import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgresChangeEvent;
import 'package:terminator/data/paged_stream.dart';

Map<String, dynamic> row(String id, [int v = 0]) => {'id': id, 'v': v};

void main() {
  group('fetchAllPages', () {
    test('single short page — one request, done', () async {
      final requested = <(int, int)>[];
      final all = await fetchAllPages(pageSize: 3, (from, to) async {
        requested.add((from, to));
        return [row('a'), row('b')];
      });
      expect(all.map((r) => r['id']), ['a', 'b']);
      expect(requested, [(0, 2)]);
    });

    test('keeps paging past full pages — the 1000-row-cap bug', () async {
      // 5 rows, page size 2 -> pages of 2, 2, 1.
      final data = [for (var i = 0; i < 5; i++) row('$i')];
      final requested = <(int, int)>[];
      final all = await fetchAllPages(pageSize: 2, (from, to) async {
        requested.add((from, to));
        return data.sublist(from, (to + 1).clamp(0, data.length));
      });
      expect(all, hasLength(5));
      expect(requested, [(0, 1), (2, 3), (4, 5)]);
    });

    test('table size exactly on the page boundary — one empty extra page',
        () async {
      final data = [for (var i = 0; i < 4; i++) row('$i')];
      final all = await fetchAllPages(pageSize: 2, (from, to) async {
        if (from >= data.length) return [];
        return data.sublist(from, (to + 1).clamp(0, data.length));
      });
      expect(all, hasLength(4));
    });

    test('empty table', () async {
      expect(await fetchAllPages((from, to) async => []), isEmpty);
    });
  });

  group('applyChange', () {
    test('insert adds a new row', () {
      final rows = [row('a')];
      applyChange(rows,
          event: PostgresChangeEvent.insert,
          newRecord: row('b'),
          oldRecord: const {},
          primaryKey: const ['id']);
      expect(rows.map((r) => r['id']), ['a', 'b']);
    });

    test('insert of an already-fetched row upserts instead of duplicating',
        () {
      final rows = [row('a', 1)];
      applyChange(rows,
          event: PostgresChangeEvent.insert,
          newRecord: row('a', 2),
          oldRecord: const {},
          primaryKey: const ['id']);
      expect(rows, hasLength(1));
      expect(rows.single['v'], 2);
    });

    test('update replaces the matching row', () {
      final rows = [row('a', 1), row('b', 1)];
      applyChange(rows,
          event: PostgresChangeEvent.update,
          newRecord: row('b', 9),
          oldRecord: row('b', 1),
          primaryKey: const ['id']);
      expect(rows[1]['v'], 9);
    });

    test('update of an unseen row adds it (how refreshes healed the bug)',
        () {
      final rows = [row('a')];
      applyChange(rows,
          event: PostgresChangeEvent.update,
          newRecord: row('z', 7),
          oldRecord: row('z', 6),
          primaryKey: const ['id']);
      expect(rows.map((r) => r['id']), ['a', 'z']);
    });

    test('delete matches on oldRecord, which carries only the primary key',
        () {
      final rows = [row('a', 1), row('b', 2)];
      applyChange(rows,
          event: PostgresChangeEvent.delete,
          newRecord: const {},
          oldRecord: {'id': 'a'},
          primaryKey: const ['id']);
      expect(rows.map((r) => r['id']), ['b']);
    });

    test('delete of an unseen row is a no-op', () {
      final rows = [row('a')];
      applyChange(rows,
          event: PostgresChangeEvent.delete,
          newRecord: const {},
          oldRecord: {'id': 'x'},
          primaryKey: const ['id']);
      expect(rows, hasLength(1));
    });

    test('composite primary key must match on every column', () {
      final rows = [
        {'slot_id': 's1', 'user_id': 'u1'},
        {'slot_id': 's1', 'user_id': 'u2'},
      ];
      applyChange(rows,
          event: PostgresChangeEvent.delete,
          newRecord: const {},
          oldRecord: {'slot_id': 's1', 'user_id': 'u2'},
          primaryKey: const ['slot_id', 'user_id']);
      expect(rows.single['user_id'], 'u1');
    });
  });
}
