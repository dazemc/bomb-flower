/// Helpers for the real-app open → edit → undo → Save As → reopen flow.
///
/// This library holds helpers only: no `main()`, no test cases, no widget
/// tree. [ui_save_flow_test] owns the flow itself. Every engine, repository
/// and session here is the production type with the production wiring, so the
/// UI flow exercises the same code path as `lib/main.dart`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/data/adapter/progress_field_value_codec.dart';
import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/io/file_save_repository.dart';
import 'package:bomb_flower/data/system/directory_picker.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/engine/save_engine.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Scrubbed sample folder the UI flow opens.
const String uiFlowFixtureName = 'kokiri-start';

/// `PlayerStatus.Life` value offset in the sample's `progress.sav`.
const int uiFlowLifeOffset = 0x14254;

/// Byte length of the sample's `progress.sav`.
const int uiFlowProgressLength = 120572;

/// Why the UI flow group is skipped when the fixture is absent.
const String uiFlowFixtureMissingReason =
    'The scrubbbed kokiri-start fixture is absent; run '
    '`dart run tool/make_fixtures.dart` from the repository root, then re-run '
    'this test.';

/// Root of the `.local-fixtures` sample save.
Directory uiFlowFixtureRoot() =>
    Directory('.local-fixtures/$uiFlowFixtureName');

/// The fixture's `slot_00/progress.sav`.
File uiFlowSourceProgress() =>
    File('${uiFlowFixtureRoot().path}/slot_00/progress.sav');

/// Whether the fixture the UI flow needs is present.
bool get uiFlowFixtureAvailable => uiFlowSourceProgress().existsSync();

/// Loads the bundled GameData schema from the repository root.
///
/// `flutter test` runs with the repository root as the working directory, so
/// this reads the same file `lib/main.dart` loads through `rootBundle`.
Future<GameDataSchema> loadUiFlowSchema() async =>
    GameDataSchema.fromJsonString(
      await File('assets/schema/gamedata_110.json').readAsString(),
    );

/// The production engine, unchanged from `ProgressSaveRepositoryFactory`.
SaveEngine createUiFlowEngine() => SaveEngine(
  const SaveFormat(
    'oot-remake',
    'Ocarina of Time (Switch 2 remake)',
    <LayoutDescriptor>[],
  ),
  valueCodec: const ProgressFieldValueCodec(),
);

/// The production repository, unchanged from
/// `ProgressSaveRepositoryFactory.create`.
FileSaveRepository createUiFlowRepository(GameDataSchema schema) {
  final engine = createUiFlowEngine();
  final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
  return FileSaveRepository(engine: engine, resolveLayout: resolver.call);
}

/// A fresh production-wired session over [schema].
SaveSessionCubit openUiFlowSession(GameDataSchema schema) {
  final engine = createUiFlowEngine();
  final resolver = ProgressLayoutResolver(ProgressLayoutBuilder(schema));
  return SaveSessionCubit(
    engine: engine,
    repository: FileSaveRepository(
      engine: engine,
      resolveLayout: resolver.call,
    ),
    resolveLayout: resolver.call,
  );
}

/// Value offset of `PlayerStatus.Life`: `0x28 + 8 * recordIndex + 4`.
int uiFlowLifeValueOffset(GameDataSchema schema) {
  final definition = schema.byNameOnDisk('PlayerStatus.Life');
  final index = definition?.recordIndex;
  if (index == null) {
    throw StateError('schema has no on-disk PlayerStatus.Life record');
  }
  return 0x28 + 8 * index + 4;
}

/// The four little-endian bytes at [offset], as `0c 00 00 00`.
String hexU32(Uint8List bytes, int offset) => <String>[
  for (var i = 0; i < 4; i++)
    bytes[offset + i].toRadixString(16).padLeft(2, '0'),
].join(' ');

/// Every index at which [a] and [b] differ; both buffers must be equal length.
List<int> differingByteIndices(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    throw ArgumentError(
      'cannot compare ${a.length} bytes with ${b.length} bytes',
    );
  }
  return <int>[
    for (var index = 0; index < a.length; index++)
      if (a[index] != b[index]) index,
  ];
}

/// Copies the fixture's `slot_00` (every file) into `<target>/slot_00`.
///
/// Throws when the fixture has no `progress.sav`, so a broken fixture fails
/// loudly instead of skipping.
void copyUiFlowSlot(Directory fixtureRoot, Directory targetRoot) {
  final source = Directory('${fixtureRoot.path}/slot_00');
  final progress = File('${source.path}/progress.sav');
  if (!progress.existsSync()) {
    throw StateError('fixture has no progress.sav at ${progress.path}');
  }
  final target = Directory('${targetRoot.path}/slot_00')
    ..createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    entity.copySync('${target.path}/${entity.uri.pathSegments.last}');
  }
}

/// Pins the widget viewport the app is designed for, and resets it on teardown.
void prepareUiFlowView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1360, 880);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Reports every destination as a fresh, creatable folder.
///
/// The UI flow saves to a path that does not exist yet, so this answer is
/// true for the Save As dialog and avoids real filesystem I/O inside the
/// fake-async test clock.
final class UiFlowFolderProbe implements SaveFolderProbe {
  /// Creates the probe.
  const UiFlowFolderProbe();

  @override
  Future<SaveFolderInfo> inspect(String path) async => SaveFolderInfo(
    path: path,
    exists: false,
    isDirectory: false,
    parentExists: true,
  );
}
