// Prints the latest changelog entry as plain text, one bullet per line —
// used by CI to fill Google Play's "What's new" (whatsnew-cs-CZ.txt) and the
// GitHub Release notes straight from the same source the app shows in-app.
//
//   dart run tool/whatsnew.dart            # latest entry
//   dart run tool/whatsnew.dart 2.0.0      # a specific version
//
// Play caps "What's new" at 500 chars per language; we trim with an ellipsis
// if an entry ever runs long (it warns on stderr so it doesn't pass silently).
import 'dart:io';

import 'package:terminator/features/team/changelog_data.dart';

void main(List<String> args) {
  final wanted = args.isNotEmpty ? args.first : null;
  final release = wanted == null
      ? appChangelog.first
      : appChangelog.firstWhere((r) => r.version == wanted,
          orElse: () => throw 'No changelog entry for $wanted');

  final text = release.changes.map((c) => '• $c').join('\n');
  if (text.length > 500) {
    stderr.writeln('warning: What\'s-new text is ${text.length} chars (>500); '
        'Play will reject it — shorten the ${release.version} entry.');
    stdout.write('${text.substring(0, 497)}...');
  } else {
    stdout.write(text);
  }
}
