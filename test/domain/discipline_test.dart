import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';

void main() {
  test('240HS is a known discipline', () {
    final d = Discipline.tryParse('240HS');
    expect(d, isNotNull);
    expect(d!.label, '240HS');
  });

  test('labels round-trip through tryParse', () {
    for (final d in Discipline.values) {
      expect(Discipline.tryParse(d.label), d);
    }
  });
}
