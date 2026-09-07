/// Signál „appka se probudila" pro živé streamy.
///
/// Supabase při přechodu do pozadí socket VĚDOMĚ odpojí a po návratu ho
/// zase spojí (supabase_flutter, _processLifecycle). Než se to stihne,
/// data na obrazovce jsou stará a wrappery čekají na svůj backoff — tenhle
/// signál je nechá přihlásit se hned.
library;

import 'dart:async';

class LiveRefresh {
  LiveRefresh._();

  static final _controller = StreamController<void>.broadcast();

  /// Posloucháte v [cachedRows]/[liveRows]; každý tick = „přetáhni data".
  static Stream<void> get stream => _controller.stream;

  /// Volá se při návratu appky do popředí (main.dart) — a kdykoli jindy,
  /// kdy má smysl přesvědčit se, že vidíme aktuální data.
  static void request() {
    if (!_controller.isClosed) _controller.add(null);
  }
}
