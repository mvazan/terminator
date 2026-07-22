/// Whole-table live stream without PostgREST's max-rows ceiling.
///
/// Supabase's `.stream()` loads its initial snapshot as ONE select, which the
/// server silently truncates to `max-rows` (default 1000). Once a table
/// outgrows that, every cold start misses rows — slots hit 2023 and Vracov
/// showed 3 of its 8 days. This helper mirrors SupabaseStreamBuilder (merge
/// by primary key, refetch after a reconnect, errors close the stream so the
/// caller's retry owns recovery) but pages the snapshot in 1000-row chunks.
/// Use it for tables that can grow past the cap (slots, availability); the
/// stock `.stream()` stays fine for the small ones.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef Rows = List<Map<String, dynamic>>;

/// One page must never exceed the server cap, or a truncated chunk would
/// look like the final (short) page and end the loop with rows missing.
const int kPageSize = 1000;

/// Fetches all pages of a table: keeps requesting [pageSize]-row windows
/// until a short page signals the end. [page] gets inclusive from/to offsets.
Future<Rows> fetchAllPages(
  Future<Rows> Function(int from, int to) page, {
  int pageSize = kPageSize,
}) async {
  final all = <Map<String, dynamic>>[];
  for (var start = 0;; start += pageSize) {
    final chunk = await page(start, start + pageSize - 1);
    all.addAll(chunk);
    if (chunk.length < pageSize) return all;
  }
}

/// Applies one Realtime change to [rows] in place, matching by [primaryKey].
/// Inserts upsert (a snapshot page may already contain the row), updates for
/// unseen rows add them (same as SupabaseStreamBuilder), deletes of unseen
/// rows are no-ops. Delete payloads carry only the primary key columns.
void applyChange(
  Rows rows, {
  required PostgresChangeEvent event,
  required Map<String, dynamic> newRecord,
  required Map<String, dynamic> oldRecord,
  required List<String> primaryKey,
}) {
  final target = event == PostgresChangeEvent.delete ? oldRecord : newRecord;
  final index = rows.indexWhere(
      (row) => primaryKey.every((col) => row[col] == target[col]));
  switch (event) {
    case PostgresChangeEvent.insert:
    case PostgresChangeEvent.update:
      if (index >= 0) {
        rows[index] = newRecord;
      } else {
        rows.add(newRecord);
      }
    case PostgresChangeEvent.delete:
      if (index >= 0) rows.removeAt(index);
    case PostgresChangeEvent.all:
      break;
  }
}

int _channelSeq = 0;

/// Streams the whole [table] like `.stream(primaryKey: ...)`, but the initial
/// snapshot (and the refetch after every Realtime reconnect) is paginated.
/// Emits a fresh row-list snapshot per change; errors are surfaced and close
/// the stream — wrap in `cachedRows`, which owns retry with backoff.
Stream<Rows> pagedTableStream(
  SupabaseClient db, {
  required String table,
  required List<String> primaryKey,
}) {
  return Stream.multi((controller) {
    final channel = db.channel('table_pages:$table:${++_channelSeq}');
    var rows = <Map<String, dynamic>>[];
    // Changes that arrive while a snapshot fetch is in flight would be
    // overwritten by it — buffer and replay them after (the stock builder
    // just drops these).
    List<PostgresChangePayload>? pendingWhileFetching;
    var everSubscribed = false;

    void emit() {
      if (!controller.isClosed) controller.add(List.of(rows));
    }

    void fail(Object error, [StackTrace? stackTrace]) {
      if (controller.isClosed) return;
      controller.addError(error, stackTrace ?? StackTrace.current);
      unawaited(channel.unsubscribe());
      controller.close();
    }

    Future<void> fetchSnapshot() async {
      final pending = pendingWhileFetching = [];
      try {
        final data = await fetchAllPages((from, to) {
          var query = db.from(table).select().order(
              primaryKey.first,
              ascending: true);
          for (final col in primaryKey.skip(1)) {
            query = query.order(col, ascending: true);
          }
          return query.range(from, to);
        });
        rows = data;
        for (final payload in pending) {
          applyChange(rows,
              event: payload.eventType,
              newRecord: payload.newRecord,
              oldRecord: payload.oldRecord,
              primaryKey: primaryKey);
        }
        emit();
      } catch (error, stackTrace) {
        fail(error, stackTrace);
      } finally {
        if (identical(pendingWhileFetching, pending)) {
          pendingWhileFetching = null;
        }
      }
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (payload) {
        final pending = pendingWhileFetching;
        if (pending != null) {
          pending.add(payload);
          return;
        }
        applyChange(rows,
            event: payload.eventType,
            newRecord: payload.newRecord,
            oldRecord: payload.oldRecord,
            primaryKey: primaryKey);
        emit();
      },
    ).subscribe((status, [error]) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          // Changes made while the socket was down were missed — reload.
          // The first snapshot is already loading (kicked off below).
          if (everSubscribed) unawaited(fetchSnapshot());
          everSubscribed = true;
        case RealtimeSubscribeStatus.closed:
          if (!controller.isClosed) controller.close();
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.channelError:
          fail(RealtimeSubscribeException(status, error));
      }
    });
    unawaited(fetchSnapshot());

    controller.onCancel = () {
      unawaited(channel.unsubscribe());
    };
  });
}
