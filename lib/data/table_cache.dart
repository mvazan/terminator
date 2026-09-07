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

import 'live_refresh.dart';

typedef Rows = List<Map<String, dynamic>>;

Directory? _dirCache;

/// Set by [clearTableCache]; pending debounced writers check it so a timer
/// firing after the wipe can't re-persist team data on a signed-out device.
/// Re-enabled when a fresh stream subscribes (next sign-in).
bool _writesEnabled = true;

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
  _writesEnabled = false;
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
/// so this wrapper owns retrying (5 s → 10 s → 30 s cap) and re-subscribes
/// the moment the app wakes up ([LiveRefresh]).
Stream<Rows> cachedRows({
  required String key,
  required Stream<Rows> Function() live,
}) =>
    _liveRows(key: key, live: live);

/// The same live stream with retry and wake-up refresh, but WITHOUT the disk
/// cache — for filtered streams whose whole-table sibling already owns the
/// cache file (chat messages of one tournament vs. the `messages` table).
/// Every live stream in the app goes through one of these two: a bare
/// `.stream()` dies with the socket and never comes back.
Stream<Rows> liveRows({required Stream<Rows> Function() live}) =>
    _liveRows(key: null, live: live);

Stream<Rows> _liveRows({
  required String? key,
  required Stream<Rows> Function() live,
}) {
  return Stream.multi((controller) {
    // A fresh subscription means a (re-)signed-in session — writing is safe.
    _writesEnabled = true;
    StreamSubscription<Rows>? sub;
    Timer? writeTimer;
    Timer? retryTimer;
    var retrySeconds = 5;
    Rows? latest;
    var emittedAnything = false;

    Future<void> emitCached() async {
      if (key == null) return;
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
        if (key == null || rows == null || !_writesEnabled) return;
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

    // Wake-up: the socket is deliberately dropped while the app sits in the
    // background, so on return the data on screen can be minutes stale (and
    // a half-open socket looks alive while delivering nothing). Re-subscribe
    // right away instead of waiting out the backoff — a fresh subscription
    // re-reads the table over HTTP, so the screen catches up even if realtime
    // is still limping. Throttled: app switching fires resumes in bursts.
    DateTime? lastWake;
    final wake = LiveRefresh.stream.listen((_) {
      final now = DateTime.now();
      if (lastWake != null &&
          now.difference(lastWake!) < const Duration(seconds: 2)) {
        return;
      }
      lastWake = now;
      retryTimer?.cancel();
      retrySeconds = 5;
      sub?.cancel();
      subscribe();
    });

    emitCached();
    subscribe();

    controller.onCancel = () {
      wake.cancel();
      sub?.cancel();
      writeTimer?.cancel();
      retryTimer?.cancel();
    };
  });
}
