import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/data/providers.dart';

void main() {
  // updateRequiredProvider only compares the two numbers; both sources are
  // overridden so no Supabase or PackageInfo is touched.
  Future<ProviderContainer> containerWith(
      {required int? minBuild, required int? build}) async {
    final c = ProviderContainer(overrides: [
      minBuildProvider.overrideWith((ref) => Stream.value(minBuild)),
      appBuildProvider.overrideWith((ref) async => build),
    ]);
    addTearDown(c.dispose);
    c.listen(updateRequiredProvider, (_, _) {});
    await c.read(minBuildProvider.future);
    await c.read(appBuildProvider.future);
    return c;
  }

  test('an older build than the backend allows requires an update', () async {
    final c = await containerWith(minBuild: 5, build: 3);
    expect(c.read(updateRequiredProvider), isTrue);
  });

  test('an equal or newer build passes', () async {
    expect((await containerWith(minBuild: 5, build: 5))
        .read(updateRequiredProvider), isFalse);
    expect((await containerWith(minBuild: 5, build: 9))
        .read(updateRequiredProvider), isFalse);
  });

  test('unknown numbers never block (offline, older backend, tests)',
      () async {
    expect((await containerWith(minBuild: null, build: 3))
        .read(updateRequiredProvider), isFalse);
    expect((await containerWith(minBuild: 5, build: null))
        .read(updateRequiredProvider), isFalse);
  });
}
