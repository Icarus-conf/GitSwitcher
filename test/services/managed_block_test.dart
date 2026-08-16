import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/services/managed_block.dart';

void main() {
  const block = ManagedBlock(beginMarker: '# >>> X', endMarker: '# <<< X');

  test('render wraps the body in markers', () {
    expect(block.render(['a', 'b']), '# >>> X\na\nb\n# <<< X');
  });

  group('replaceIn', () {
    test('appends when no markers are present', () {
      expect(
        block.replaceIn('keep me\n', '# >>> X\nnew\n# <<< X'),
        'keep me\n\n# >>> X\nnew\n# <<< X\n',
      );
    });

    test('appends to empty content with no leading blank line', () {
      expect(block.replaceIn('', 'B'), 'B\n');
    });

    test('replaces in place and preserves both sides', () {
      const existing = 'before\n\n# >>> X\nold\n# <<< X\n\nafter\n';

      expect(
        block.replaceIn(existing, '# >>> X\nnew\n# <<< X'),
        'before\n\n# >>> X\nnew\n# <<< X\n\nafter\n',
      );
    });

    test('throws when the closing marker is missing', () {
      expect(
        () => block.replaceIn('# >>> X\nbody\n', 'B'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when the markers are inverted', () {
      expect(
        () => block.replaceIn('# <<< X\n# >>> X\n', 'B'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('removeFrom', () {
    test('removes the block and keeps surrounding content', () {
      const existing = 'before\n\n# >>> X\nold\n# <<< X\n\nafter\n';

      expect(block.removeFrom(existing), 'before\n\nafter\n');
    });

    test('returns the input unchanged when no block is present', () {
      expect(block.removeFrom('nothing here\n'), 'nothing here\n');
    });

    test('leaves an empty file when the block was the only content', () {
      expect(block.removeFrom('# >>> X\nold\n# <<< X\n'), '');
    });

    test('install then remove restores the original text', () {
      const original = 'export PATH=/usr/bin\n';
      final installed = block.replaceIn(original, block.render(['hook']));

      expect(block.removeFrom(installed), original);
    });
  });

  test('isPresentIn detects the block', () {
    expect(block.isPresentIn('# >>> X\n'), isTrue);
    expect(block.isPresentIn('unrelated'), isFalse);
  });

  test('BackupWriter writes a timestamped copy', () async {
    final tempDir = Directory.systemTemp.createTempSync('gitswitcher_backup');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final file = File('${tempDir.path}/config');

    final backup = await BackupWriter(
      now: () => DateTime.fromMillisecondsSinceEpoch(42),
    ).write(file, 'original contents');

    expect(backup.path, endsWith('.gitswitcher-backup-42'));
    expect(backup.readAsStringSync(), 'original contents');
  });
}
