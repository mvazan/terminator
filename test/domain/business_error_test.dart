import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/core/ui.dart';

void main() {
  // Verbatim from Sentry (TERMINATOR-B/C, 2.4.0): a stale roster list after
  // the realtime stream timed out, so "add" hit a row that already existed.
  const rosterDuplicate =
      'PostgrestException(message: duplicate key value violates unique '
      'constraint "rosters_slot_user_idx", code: 23505, details: Conflict, '
      'hint: null)';

  test('duplicate roster entry reads as a human sentence, not SQL', () {
    final message = businessError(rosterDuplicate);
    expect(message, isNotNull);
    expect(message, contains('už na startu je'));
    // The point of the mapping: no constraint names or error codes leak out.
    expect(message, isNot(contains('rosters_slot_user_idx')));
    expect(message, isNot(contains('23505')));
  });

  test('duplicate chat mute is explained too', () {
    expect(
      businessError('PostgrestException(message: duplicate key value violates '
          'unique constraint "chat_mutes_unique_idx", code: 23505)'),
      contains('ztlumený'),
    );
  });

  test('existing rules still map', () {
    expect(businessError('... not_a_teammate ...'), isNotNull);
    expect(businessError('... forbidden ...'), 'Na tohle nemáš oprávnění.');
  });

  // Anything unrecognised must stay null so tryAction still reports it to
  // Sentry — swallowing unknown failures is how real defects go unnoticed.
  test('unknown failures are not swallowed', () {
    expect(businessError('PostgrestException(message: relation "x" does not '
        'exist, code: 42P01)'), isNull);
    expect(businessError('Some random failure'), isNull);
  });
}
