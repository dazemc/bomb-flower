import 'dart:async';

import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// A launched dialog plus the future that completes when it closes.
final class DialogLauncher<T> {
  DialogLauncher(this.completer) : future = completer.future;

  /// Completes with the dialog's result once the route pops.
  final Future<T?> future;

  /// The backing completer, exposed so a stalled case can be diagnosed.
  final Completer<T?> completer;

  /// Whether the dialog has already delivered its result.
  bool get isCompleted => completer.isCompleted;
}

/// Pumps a themed host and opens [show] from a button press.
Future<DialogLauncher<T>> launchDialog<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) show, {
  Size size = const Size(900, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final completer = Completer<T?>();
  // Every path that completes the completer goes through this guard, so a
  // second completion can never throw "Already completed".
  void completeIfPending(T? value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  addTearDown(() => completeIfPending(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('dialog-launch'),
              onPressed: () async {
                final value = await show(context);
                completeIfPending(value);
              },
              child: const Text('Launch'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('dialog-launch')));
  await tester.pumpAndSettle();
  return DialogLauncher<T>(completer);
}

/// A probe backed by a fixed map of folder descriptions.
final class FakeSaveFolderProbe implements SaveFolderProbe {
  FakeSaveFolderProbe([Map<String, SaveFolderInfo>? folders])
    : folders = folders ?? <String, SaveFolderInfo>{};

  final Map<String, SaveFolderInfo> folders;
  final List<String> inspected = <String>[];
  SaveFolderInfo? fallback;

  @override
  Future<SaveFolderInfo> inspect(String path) async {
    final trimmed = path.trim();
    inspected.add(trimmed);
    return folders[trimmed] ??
        fallback ??
        SaveFolderInfo(path: trimmed, exists: false, isDirectory: false);
  }
}

/// In-memory recent-path store.
final class FakeRecentPathsStore implements RecentPathsStore {
  FakeRecentPathsStore([List<String>? initial]) : paths = initial ?? <String>[];

  List<String> paths;
  final List<String> added = <String>[];
  int reads = 0;

  @override
  Future<List<String>> read() async {
    reads++;
    return List<String>.of(paths);
  }

  @override
  Future<void> add(String path) async {
    added.add(path);
    paths = <String>[
      path,
      for (final entry in paths)
        if (entry != path) entry,
    ];
  }

  @override
  Future<void> clear() async {
    paths = <String>[];
  }
}

/// Scripted native folder picker.
final class FakeDirectoryPicker implements DirectoryPicker {
  FakeDirectoryPicker({this.result, this.throws = false});

  String? result;
  bool throws = false;
  int calls = 0;
  String? lastInitialPath;

  @override
  Future<String?> pickDirectory({String? title, String? initialPath}) async {
    calls++;
    lastInitialPath = initialPath;
    if (throws) {
      throw StateError('picker failed');
    }
    return result;
  }
}
