import 'dart:io';

import 'package:bomb_flower/data/system/longshot_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real-filesystem behaviour of [IoLongshotLauncher], tested outside a widget
/// binding so `stat()` actually completes.
void main() {
  test('a path that does not exist is missing and never started', () async {
    const path = '/tmp/opencode/bf-longshot-missing-9f2c/launcher';

    final result = await const IoLongshotLauncher().launch(path);

    expect(result.status, LaunchStatus.missing);
    expect(result.started, isFalse);
    expect(result.path, path);
    expect(result.message, contains(path));
  });

  test('a non-executable file is reported notExecutable', () async {
    final temp = Directory.systemTemp.createTempSync('bf-launcher-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/longshot-launcher')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    final chmod = Process.runSync('chmod', <String>['644', file.path]);
    expect(chmod.exitCode, 0, reason: 'test setup could not chmod the file');

    final result = await const IoLongshotLauncher().launch(file.path);

    expect(result.status, LaunchStatus.notExecutable);
    expect(result.started, isFalse);
    expect(result.path, file.path);
    expect(result.message, contains(file.path));
  });

  test('an empty path never produces a dangling colon', () {
    // `launch('')` classifies as missing before statting; the other two
    // statuses cannot arise from an empty path, but the message guards them
    // too so no future call site can surface "not found: ".
    for (final status in <LaunchStatus>[
      LaunchStatus.missing,
      LaunchStatus.notExecutable,
      LaunchStatus.failed,
    ]) {
      final message = LaunchResult(status: status, path: '').message;
      expect(message, kNoLongshotLauncherConfigured);
      expect(message, isNot(endsWith(':')));
    }
  });

  // An executable path is deliberately not exercised here: the only way to
  // observe [LaunchStatus.started] from the real implementation is to actually
  // start the process, which a unit test must not do.
}
