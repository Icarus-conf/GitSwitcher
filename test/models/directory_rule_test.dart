import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/directory_rule.dart';

void main() {
  // Matching is git's job now (includeIf gitdir); see git_config_writer_test.
  test('round-trips through JSON', () {
    const work = DirectoryRule(pathPrefix: '~/work', ghUsername: 'work-user');
    expect(DirectoryRule.fromJson(work.toJson()), work);
  });
}
