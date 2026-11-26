@TestOn('mac-os || linux') // Runs the bash script with shasum/sha256sum.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drives tool/publish_release.sh against a fake `gh` that can fail the way
/// GitHub's release API really does: errors that lose the work, and errors
/// reported after the work already happened.
void main() {
  late Directory temp;
  late Directory state;
  late Directory notes;
  late List<String> zips;

  const fakeGh = r'''#!/usr/bin/env bash
S="$FAKE_GH_STATE"
# fail OP: true (and counts down) while fail_OP holds a number above zero.
fail() {
  local f="$S/fail_$1"
  [ -f "$f" ] || return 1
  local n; n=$(cat "$f")
  [ "$n" -gt 0 ] || return 1
  echo $((n - 1)) > "$f"
}
case "$1 $2" in
  "api repos/"*)
    if fail api; then echo "HTTP 502: Server Error" >&2; exit 1; fi
    [ -f "$S/release" ] || { echo "HTTP 404: Not Found" >&2; exit 1; }
    if [ "${3:-}" = "--jq" ]; then
      name=$(sed -E 's/.*\.name == "([^"]+)".*/\1/' <<<"$4")
      [ -f "$S/assets/$name" ] && cat "$S/assets/$name"
    else
      echo '{}'
    fi
    exit 0 ;;
  "release create")
    echo create >> "$S/calls"
    while [ $# -gt 0 ]; do
      [ "$1" = "--notes-file" ] && cp "$2" "$S/notes"
      shift
    done
    touch "$S/release"
    if fail create; then echo "HTTP 500" >&2; exit 1; fi
    exit 0 ;;
  "release upload")
    file="$4"; name=$(basename "$file")
    echo "upload $name" >> "$S/calls"
    if fail upload_lost; then echo "HTTP 502" >&2; exit 1; fi
    mkdir -p "$S/assets"
    echo "sha256:$(shasum -a 256 "$file" | cut -d' ' -f1)" > "$S/assets/$name"
    if fail upload_err; then echo "HTTP 500" >&2; exit 1; fi
    exit 0 ;;
esac
echo "fake gh: unexpected $*" >&2; exit 99
''';

  setUp(() {
    temp = Directory.systemTemp.createTempSync('gitswitcher_publish');
    state = Directory('${temp.path}/state')..createSync();
    notes = Directory('${temp.path}/notes')..createSync();
    File('${notes.path}/default.md').writeAsStringSync('default notes');
    final bin = Directory('${temp.path}/bin')..createSync();
    File('${bin.path}/gh').writeAsStringSync(fakeGh);
    Process.runSync('/bin/chmod', ['755', '${bin.path}/gh']);
    zips = [
      for (final os in ['macos', 'windows'])
        (File('${temp.path}/GitSwitcher-v9.9.9-$os.zip')
              ..writeAsStringSync('zip for $os'))
            .path,
    ];
  });

  tearDown(() => temp.deleteSync(recursive: true));

  void failNext(String op, int times) =>
      File('${state.path}/fail_$op').writeAsStringSync('$times');

  List<String> calls() {
    final f = File('${state.path}/calls');
    return f.existsSync() ? f.readAsLinesSync() : [];
  }

  ProcessResult publish({int attempts = 6}) => Process.runSync(
        'bash',
        ['tool/publish_release.sh', 'v9.9.9', ...zips],
        environment: {
          'PATH': '${temp.path}/bin:${Platform.environment['PATH']}',
          'FAKE_GH_STATE': state.path,
          'GH_REPO': 'o/r',
          'NOTES_DIR': notes.path,
          'ATTEMPTS': '$attempts',
          'DELAY': '0',
        },
      );

  void expectOk(ProcessResult r) =>
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');

  test('creates the release and uploads both zips, verified', () {
    expectOk(publish());

    expect(calls(), [
      'create',
      'upload GitSwitcher-v9.9.9-macos.zip',
      'upload GitSwitcher-v9.9.9-windows.zip',
    ]);
    expect(File('${state.path}/notes').readAsStringSync(), 'default notes');
  });

  test("uses the tag's own notes when they exist", () {
    File('${notes.path}/v9.9.9.md').writeAsStringSync("what's new");

    expectOk(publish());

    expect(File('${state.path}/notes').readAsStringSync(), "what's new");
  });

  test('an existing release keeps its notes; only the zips are uploaded', () {
    File('${state.path}/release').createSync();

    expectOk(publish());

    expect(calls(), isNot(contains('create')));
  });

  test('a create that errors but worked is not repeated', () {
    failNext('create', 1);

    expectOk(publish());

    expect(calls().where((c) => c == 'create'), hasLength(1));
  });

  test('cannot tell whether the release exists: asks again, never guesses',
      () {
    failNext('api', 2);

    expectOk(publish());

    expect(calls().where((c) => c == 'create'), hasLength(1));
  });

  test('an upload that errors but arrived is checked, not repeated', () {
    // What happened on v0.2.1: HTTP 500 on a complete upload.
    failNext('upload_err', 1);

    expectOk(publish());

    expect(calls().where((c) => c.contains('macos')), hasLength(1));
  });

  test('an upload that was lost is retried until it is there', () {
    failNext('upload_lost', 2);

    expectOk(publish());

    expect(calls().where((c) => c.contains('macos')), hasLength(3));
  });

  test('gives up, failing the job, when GitHub never takes the file', () {
    failNext('upload_lost', 99);

    final r = publish(attempts: 3);

    expect(r.exitCode, isNot(0));
    expect(r.stdout, contains('gave up after 3 attempts'));
  });
}
