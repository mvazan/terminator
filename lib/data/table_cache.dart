/// Read-only offline cache for the whole-table Realtime streams.
///
/// Every stream snapshot is persisted as one JSON file per table; on the next
/// (possibly offline) launch the cached rows are emitted first, then the live
/// stream takes over. When the live stream errors (no network, server down),
/// the error is swallowed — the last known data stays on screen — and the
/// subscription retries with backoff. Cached data is plaintext on the user's
/// own device; the one hygiene rule is that sign-out wipes it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

typedef Rows = List<Map<String, dynamic>>;

Directory? _dirCache;

Future<Directory> _cacheDir() async {
  if (_dirCache != null) return _dirCache!;
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/table_cache');
  await dir.create(recursive: true);
  return _dirCache = dir;
}

Future<File> _fileFor(String key) async =>
    File('${(await _cacheDir()).path}/$key.json');

/// Wipes all cached tables — called on sign-out so a shared/returned device
/// doesn't keep team data readable.
Future<void> clearTableCache() async {
  try {
    final dir = await _cacheDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dirCache = null;
  } catch (e) {
    debugPrint('table cache clear failed: $e');
  }
}

/// Wraps a live table stream with the disk cache: cached rows first (if any),
/// then live snapshots, each persisted (debounced). Live errors don't reach
/// the listener — Supabase's .stream() terminates on a failed initial fetch,
/// so this wrapper owns retrying (5 s → 10 s → 30 s cap).
Stream<Rows> cachedRows({
  required String key,
  required Stream<Rows> Function() live,
}) {
  return Stream.multi((controller) {
    StreamSubscription<Rows>? sub;
    Timer? writeTimer;
    Timer? retryTimer;
    var retrySeconds = 5;
    Rows? latest;
    var emittedAnything = false;

    Future<void> emitCached() async {
      try {
        final file = await _fileFor(key);
        if (!await file.exists()) return;
        final decoded = jsonDecode(await file.readAsString());
        final rows = [
          for (final row in decoded as List) (row as Map).cast<String, dynamic>(),
        ];
        // Live data may have arrived while we were reading the file — don't
        // regress to the older cached snapshot.
        if (!emittedAnything && !controller.isClosed) {
          emittedAnything = true;
          controller.add(rows);
        }
      } catch (e) {
        debugPrint('table cache read failed ($key): $e');
      }
    }

    void scheduleWrite() {
      writeTimer?.cancel();
      writeTimer = Timer(const Duration(seconds: 2), () async {
        final rows = latest;
        if (rows == null) return;
        try {
          final file = await _fileFor(key);
          await file.writeAsString(jsonEncode(rows));
        } catch (e) {
          debugPrint('table cache write failed ($key): $e');
        }
      });
    }

    void subscribe() {
      sub = live().listen(
        (rows) {
          retrySeconds = 5; // healthy again
          latest = rows;
          emittedAnything = true;
          if (!controller.isClosed) controller.add(rows);
          scheduleWrite();
        },
        onError: (Object e, StackTrace _) {
          // Offline/server error: keep showing what we have and retry.
          debugPrint('live stream error ($key), retrying: $e');
          sub?.cancel();
          retryTimer = Timer(Duration(seconds: retrySeconds), subscribe);
          retrySeconds = (retrySeconds * 2).clamp(5, 30);
        },
        onDone: () {
          // Realtime closed the stream (e.g. socket loss) — same treatment.
          retryTimer = Timer(Duration(seconds: retrySeconds), subscribe);
          retrySeconds = (retrySeconds * 2).clamp(5, 30);
        },
      );
    }

    emitCached();
    subscribe();

    controller.onCancel = () {
      sub?.cancel();
      writeTimer?.cancel();
      retryTimer?.cancel();
    };
  });
}
