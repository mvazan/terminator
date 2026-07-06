import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';

void main() {
  final noon = DateTime.utc(2026, 7, 6, 12);

  test('missing row uses the per-kind default', () {
    // Opt-in kinds (user decision): silent until enabled in settings.
    expect(NotificationPref.fallback(NotificationKind.newMember).enabled,
        isFalse);
    expect(NotificationPref.fallback(NotificationKind.threshold).enabled,
        isFalse);
    // Everything else is on out of the box.
    for (final kind in [
      NotificationKind.newTournament,
      NotificationKind.proposal,
      NotificationKind.order,
      NotificationKind.chat,
    ]) {
      final pref = NotificationPref.fallback(kind);
      expect(pref.enabled, isTrue);
      expect(pref.isActiveAt(noon), isTrue);
    }
  });

  test('disabled kind is never active', () {
    const pref = NotificationPref(
        kind: NotificationKind.chat, enabled: false);
    expect(pref.isActiveAt(noon), isFalse);
  });

  test('mute silences until the timestamp, then wakes up on its own', () {
    final pref = NotificationPref(
      kind: NotificationKind.order,
      enabled: true,
      mutedUntil: noon.add(const Duration(hours: 3)),
    );
    expect(pref.isActiveAt(noon), isFalse);
    expect(pref.isMutedAt(noon), isTrue);
    expect(pref.isActiveAt(noon.add(const Duration(hours: 3))), isTrue);
  });

  test('expired mute on a disabled kind stays inactive', () {
    final pref = NotificationPref(
      kind: NotificationKind.proposal,
      enabled: false,
      mutedUntil: noon.subtract(const Duration(hours: 1)),
    );
    expect(pref.isActiveAt(noon), isFalse);
  });

  test('sql names round-trip', () {
    for (final kind in NotificationKind.values) {
      expect(NotificationKind.tryParse(kind.sqlName), kind);
    }
    expect(NotificationKind.tryParse('nonsense'), isNull);
  });
}
