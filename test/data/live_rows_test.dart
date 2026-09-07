import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/data/live_refresh.dart';
import 'package:terminator/data/table_cache.dart';

/// Tovární funkce, která pokaždé vrátí nový ovladatelný stream — test tak
/// vidí, kolikrát se wrapper znovu přihlásil, a řídí, co každý pokus udělá.
class _Factory {
  final controllers = <StreamController<Rows>>[];

  Stream<Rows> call() {
    final c = StreamController<Rows>();
    controllers.add(c);
    return c.stream;
  }

  StreamController<Rows> get last => controllers.last;
  int get subscriptions => controllers.length;
}

void main() {
  test('rows z živého streamu propadnou k posluchači', () {
    fakeAsync((async) {
      final factory = _Factory();
      final seen = <Rows>[];
      final sub = liveRows(live: factory.call).listen(seen.add);
      async.flushMicrotasks();

      factory.last.add([
        {'id': '1'},
      ]);
      async.flushMicrotasks();

      expect(seen, hasLength(1));
      expect(seen.single.single['id'], '1');
      sub.cancel();
    });
  });

  test('chyba streamu se k posluchači nedostane a přihlásí se znovu', () {
    fakeAsync((async) {
      final factory = _Factory();
      final seen = <Rows>[];
      Object? seenError;
      final sub = liveRows(live: factory.call)
          .listen(seen.add, onError: (Object e) => seenError = e);
      async.flushMicrotasks();

      factory.last.addError(Exception('offline'));
      async.flushMicrotasks();
      expect(seenError, isNull, reason: 'poslední známá data zůstávají');
      expect(factory.subscriptions, 1, reason: 'zatím čeká na backoff');

      async.elapse(const Duration(seconds: 5));
      expect(factory.subscriptions, 2);

      factory.last.add([
        {'id': 'po chybě'},
      ]);
      async.flushMicrotasks();
      expect(seen.single.single['id'], 'po chybě');
      sub.cancel();
    });
  });

  test('ukončený stream (spadlý socket) se také obnoví', () {
    fakeAsync((async) {
      final factory = _Factory();
      final sub = liveRows(live: factory.call).listen((_) {});
      async.flushMicrotasks();

      factory.last.close();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));

      expect(factory.subscriptions, 2);
      sub.cancel();
    });
  });

  test('probuzení appky se přihlásí hned, bez čekání na backoff', () {
    fakeAsync((async) {
      final factory = _Factory();
      final seen = <Rows>[];
      final sub = liveRows(live: factory.call).listen(seen.add);
      async.flushMicrotasks();

      factory.last.addError(Exception('offline'));
      async.flushMicrotasks();
      expect(factory.subscriptions, 1);

      LiveRefresh.request();
      async.flushMicrotasks();
      expect(factory.subscriptions, 2, reason: 'hned, ne za 5 s');

      factory.last.add([
        {'id': 'po probuzení'},
      ]);
      async.flushMicrotasks();
      expect(seen.single.single['id'], 'po probuzení');
      sub.cancel();
    });
  });

  test('zdravý stream se na probuzení přihlásí znovu — socket může být '
      'zdánlivě živý (half-open) a data zastaralá', () {
    fakeAsync((async) {
      final factory = _Factory();
      final sub = liveRows(live: factory.call).listen((_) {});
      async.flushMicrotasks();
      factory.last.add([
        {'id': '1'},
      ]);
      async.flushMicrotasks();

      LiveRefresh.request();
      async.flushMicrotasks();
      expect(factory.subscriptions, 2);
      sub.cancel();
    });
  });

  test('rychlé probuzení za sebou streamy nezahltí', () {
    fakeAsync((async) {
      final factory = _Factory();
      final sub = liveRows(live: factory.call).listen((_) {});
      async.flushMicrotasks();

      LiveRefresh.request();
      async.flushMicrotasks();
      LiveRefresh.request();
      async.flushMicrotasks();

      expect(factory.subscriptions, 2, reason: 'druhý tick je moc brzo');
      sub.cancel();
    });
  });
}
