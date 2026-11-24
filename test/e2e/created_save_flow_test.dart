/// End-to-end proof that a created save is a usable artifact through the app.
///
/// The save is built by the production [NewSaveBuilder] + [NewSaveWriter] pair
/// (the same one the in-app dialog runs), written into this run's own unique
/// `.tmp/` root, opened through the production [SaveSessionCubit] wiring, and
/// then rendered by the real shell. Three inline scalar fields are edited in
/// three different tabs through the tab controls, saved in place, reopened,
/// byte-diffed, and exported with Save As. Nothing here touches
/// `.local-fixtures/`, `~/.local/share/longshot`, or the game.
///
/// The measured facts are printed as `[e2e] ...` lines so a gate log is the
/// evidence, and every printed number is asserted.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bomb_flower/app.dart';
import 'package:bomb_flower/data/adapter/progress_layout_builder.dart';
import 'package:bomb_flower/data/adapter/progress_layout_resolver.dart';
import 'package:bomb_flower/data/io/file_save_repository.dart';
import 'package:bomb_flower/data/newsave/new_save_writer.dart';
import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/domain/newsave/new_save_builder.dart';
import 'package:bomb_flower/domain/newsave/new_save_spec.dart';
import 'package:bomb_flower/domain/schema/gamedata_schema.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_cubit.dart';
import 'package:bomb_flower/presentation/bloc/save_session/save_session_ui_state.dart';
import 'package:bomb_flower/presentation/bloc/shell/shell_cubit.dart';
import 'package:bomb_flower/presentation/bloc/shell/tab_definition.dart';
import 'package:bomb_flower/presentation/shell/app_shell.dart';
import 'package:bomb_flower/presentation/shell/tabs/advanced_data_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/resources_tab.dart';
import 'package:bomb_flower/presentation/shell/tabs/settings_tab.dart';
import 'package:bomb_flower/presentation/tabs_support/bundled_catalogues.dart';
import 'package:bomb_flower/presentation/widgets/common/empty_state.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/data/edit_table.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../integration/support/progress_chain.dart';
import '../support/byte_assert.dart';
import '../support/temp_roots.dart';

/// The three verified inline scalars this flow edits, one per tab.
///
/// Each is a 4-byte value word in the record table, so an edit can only touch
/// its own span. `PlayerStatus.MaxLife` is raised first so the unchanged
/// `PlayerStatus.Life` (12) stays within `Life <= MaxLife`.
const String _maxLifeName = 'PlayerStatus.MaxLife';
const String _flagName = 'ActionGuide_IsEnd.Bomb';
const String _tokenStockName = 'PouchData.Item_Token_Gold.StockNum';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameDataSchema schema;

  setUpAll(() async {
    schema = await loadGameDataSchema();
    // Prime rootBundle's string cache outside the fake-async widget clock, so
    // the scene catalogue resolves in the widget test.
    await rootBundle.loadString('assets/world/scenes.json');
    // The catalogue tabs share a process-wide parsed future; awaiting it here
    // means the widget test's FutureBuilder starts from a completed future.
    await loadFieldGroupsCatalogueOnce();
    await loadActorCatalogueOnce();
  });

  testWidgets('a created save renders, edits, saves, reopens and exports', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1360, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // ---- 1. Create the artifact with the production builder + writer. ----
    final scratch = createTempRoot('e2e/created-save-flow');
    addTearDown(() => removeTempRoot(scratch));
    final createdRoot = '${scratch.path}/created';
    final build = NewSaveBuilder.build(
      schema: schema,
      spec: NewSaveSpec.preset(NewSavePreset.schemaDefaults),
    );
    final write = await tester.runAsync(
      () => NewSaveWriter().write(rootDirectory: createdRoot, build: build),
    );
    expect(write, isNotNull, reason: 'the new-save writer must return');
    final progressFile = File('$createdRoot/slot_00/progress.sav');
    final captionFile = File('$createdRoot/slot_00/caption.sav');
    final originalProgress = progressFile.readAsBytesSync();
    final originalCaption = captionFile.readAsBytesSync();
    expect(originalProgress, hasLength(120572));
    expect(originalCaption, hasLength(2029));
    stdout.writeln(
      '[e2e] created root=$createdRoot '
      'progress=${originalProgress.length} caption=${originalCaption.length}',
    );

    // ---- 2. Open it through the production cubit wiring. ----
    final cubit = _buildCubit(schema);
    addTearDown(() async {
      if (!cubit.isClosed) {
        await cubit.close(force: true);
      }
    });
    await tester.runAsync(() => cubit.openPath(createdRoot));
    expect(cubit.state, isA<SaveSessionReady>());
    final openResult = cubit.lastOpenResult;
    // A created save carries 8,317 hash-only records, so the engine reports
    // ParseUnverified by design; what matters is that nothing is blocking.
    expect(openResult, isA<ParseUnverified>());
    final unverified = (openResult! as ParseUnverified).unverifiedFields;
    final project = cubit.openProject;
    expect(project, isNotNull);
    final opened = project!;
    final ready = cubit.state as SaveSessionReady;
    final blocking = ready.project.issues
        .where((issue) => issue.isBlocking)
        .toList(growable: false);
    expect(blocking, isEmpty, reason: 'blocking: $blocking');
    expect(opened.documents.keys, contains(progressSlotId));
    stdout.writeln(
      '[e2e] open=ParseUnverified unverifiedFields=${unverified.length} '
      'blocking=0 slots=${opened.documents.length}',
    );

    // ---- 3. Render all eleven tabs through the real shell. ----
    await tester.pumpWidget(
      BombFlowerApp(enableWindowChrome: false, session: cubit),
    );
    await tester.pumpAndSettle();
    final shell = BlocProvider.of<ShellCubit>(
      tester.element(find.byType(AppShell)),
    );

    expect(ShellTab.values, hasLength(11));
    for (final tab in ShellTab.values) {
      await _showTab(tester, shell, tab);

      final page = find.byKey(Key('tab-page-${tab.name}'));
      expect(page, findsOneWidget, reason: '${tab.name}: page key missing');
      expect(
        tester.takeException(),
        isNull,
        reason: '${tab.name}: the page threw while building',
      );
      expect(
        find.descendant(of: page, matching: find.byType(EmptyState)),
        findsNothing,
        reason: '${tab.name}: rendered the empty state for an open save',
      );
      expect(
        _contentFor(tab),
        findsWidgets,
        reason: '${tab.name}: expected real content ${_contentFor(tab)}',
      );
      stdout.writeln('[e2e] tab=${tab.name} displayed=${_contentLabel(tab)}');
    }

    // ---- 4. Edit three fields in three different tabs, through their UI. ----
    final maxLifeId = _fieldId(schema, _maxLifeName);
    final flagId = _fieldId(schema, _flagName);
    final tokenStockId = _fieldId(schema, _tokenStockName);
    final maxLifeSpan = _valueSpan(schema, _maxLifeName);
    final flagSpan = _valueSpan(schema, _flagName);
    final tokenStockSpan = _valueSpan(schema, _tokenStockName);

    // The three ids and spans must be the layout's own inline value words.
    for (final entry in <(String, FieldId, ByteSpan)>[
      (_maxLifeName, maxLifeId, maxLifeSpan),
      (_flagName, flagId, flagSpan),
      (_tokenStockName, tokenStockId, tokenStockSpan),
    ]) {
      final descriptor = opened.layout.descriptor(entry.$2);
      expect(descriptor, isNotNull, reason: '${entry.$1} is not in the layout');
      expect(descriptor!.label, entry.$1);
      expect(descriptor.span, entry.$3);
      expect(descriptor.span.length, 4);
      expect(descriptor.isEditable, isTrue, reason: '${entry.$1} is read-only');
    }

    // Defaults before any edit, so the recorded from/to values are measured.
    expect(_intOf(opened, maxLifeId), 12);
    expect(_boolOf(opened, flagId), isFalse);
    expect(_intOf(opened, tokenStockId), 0);

    // Resources: MaxLife 12 -> 24 through the real NumericField.
    await _showTab(tester, shell, ShellTab.resources);
    final maxLifeInput = find.descendant(
      of: find.byKey(ResourcesTab.maxLifeFieldKey),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(maxLifeInput);
    await tester.pumpAndSettle();
    await tester.enterText(maxLifeInput, '24');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(cubit.state, isA<SaveSessionReady>());
    expect(
      tester
          .widget<NumericField>(
            find.descendant(
              of: find.byKey(ResourcesTab.maxLifeFieldKey),
              matching: find.byType(NumericField),
            ),
          )
          .value,
      24,
    );
    _reportEdit('resources', _maxLifeName, maxLifeId, maxLifeSpan, 12, 24);

    // Flags: ActionGuide_IsEnd.Bomb false -> true through the row's toggle.
    await _showTab(tester, shell, ShellTab.flags);
    await _searchEditTable(tester, _flagName);
    final flagCell = find.byKey(Key('edit-table-cell-${flagId.value}'));
    await tester.ensureVisible(flagCell);
    await tester.pumpAndSettle();
    await tester.tap(flagCell);
    await tester.pumpAndSettle();
    expect(cubit.state, isA<SaveSessionReady>());
    expect(tester.widget<BrassToggle>(flagCell).value, isTrue);
    _reportEdit('flags', _flagName, flagId, flagSpan, 0, 1);

    // Collectibles: token stock 0 -> 5 through the row's NumericField.
    await _showTab(tester, shell, ShellTab.collectibles);
    await _searchEditTable(tester, _tokenStockName);
    final stockCell = find.byKey(Key('edit-table-cell-${tokenStockId.value}'));
    await tester.ensureVisible(stockCell);
    await tester.pumpAndSettle();
    final stockInput = find.descendant(
      of: stockCell,
      matching: find.byType(TextField),
    );
    await tester.enterText(stockInput, '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(cubit.state, isA<SaveSessionReady>());
    expect(tester.widget<NumericField>(stockCell).value, 5);
    _reportEdit(
      'collectibles',
      _tokenStockName,
      tokenStockId,
      tokenStockSpan,
      0,
      5,
    );

    // The live project carries exactly the three edits and nothing else.
    final dirty = (cubit.state as SaveSessionReady).project;
    expect(dirty.changedFieldCount, 3);
    expect(dirty.changedByteCount, 3);

    // ---- 5. Save in place and prove the bytes. ----
    await tester.runAsync(() => cubit.save());
    await tester.pumpAndSettle();
    final savedState = cubit.state;
    expect(savedState, isA<SaveSessionSaved>());
    final saved = savedState as SaveSessionSaved;
    expect(saved.mode, ExportMode.saveInPlace);
    expect(saved.path, createdRoot);
    final captionSlotId = SaveSlotId('${progressSlotId.value}.caption');
    expect(
      saved.written.map((write) => write.slot),
      containsAll(<SaveSlotId>[progressSlotId, captionSlotId]),
    );
    stdout.writeln(
      '[e2e] save mode=${saved.mode.name} path=${saved.path} '
      'written=${saved.written.length}',
    );

    final savedProgress = progressFile.readAsBytesSync();
    final savedCaption = captionFile.readAsBytesSync();
    expect(savedProgress.length, originalProgress.length);
    expectByteIdentical(savedCaption, originalCaption);

    final spans = <ByteSpan>[maxLifeSpan, flagSpan, tokenStockSpan];
    final union = <int>{
      for (final span in spans)
        for (var offset = span.offset; offset < span.end; offset++) offset,
    };
    final differing = <int>[
      for (var index = 0; index < originalProgress.length; index++)
        if (originalProgress[index] != savedProgress[index]) index,
    ];
    expect(
      differing.where((offset) => !union.contains(offset)),
      isEmpty,
      reason: 'a byte outside the three value-word spans changed',
    );
    for (final span in spans) {
      expect(
        differing.where((offset) => offset >= span.offset && offset < span.end),
        isNotEmpty,
        reason: 'the edit in ${span.offset}..${span.end} left no byte behind',
      );
      // The record table only: never the header, sentinels, footer or tail.
      expect(span.offset, greaterThanOrEqualTo(0x28));
      expect(span.end, lessThanOrEqualTo(0x175d8));
    }
    expect(differing, hasLength(3));
    stdout.writeln(
      '[e2e] diff length=${savedProgress.length} differing=${differing.length} '
      'offsets=${differing.map(_hexOffset).join(',')} '
      'spans=${spans.map((span) => '${_hexOffset(span.offset)}..'
          '${_hexOffset(span.end)}').join(',')}',
    );
    for (final entry in <(FieldId, ByteSpan, int)>[
      (maxLifeId, maxLifeSpan, 24),
      (flagId, flagSpan, 1),
      (tokenStockId, tokenStockSpan, 5),
    ]) {
      expect(
        ByteData.sublistView(
          savedProgress,
          entry.$2.offset,
          entry.$2.end,
        ).getUint32(0, Endian.little),
        entry.$3,
        reason: 'disk value at ${_hexOffset(entry.$2.offset)}',
      );
    }

    // The repository's standard policy keeps one `.bak` of the previous file.
    final progressBak = File('${progressFile.path}.bak');
    final captionBak = File('${captionFile.path}.bak');
    expect(progressBak.existsSync(), isTrue, reason: 'no progress.sav.bak');
    expect(captionBak.existsSync(), isTrue, reason: 'no caption.sav.bak');
    expectByteIdentical(progressBak.readAsBytesSync(), originalProgress);
    expectByteIdentical(captionBak.readAsBytesSync(), originalCaption);
    stdout.writeln(
      '[e2e] backup progress.sav.bak=${progressBak.lengthSync()} identical=true '
      'caption.sav.bak=${captionBak.lengthSync()} identical=true',
    );

    // ---- 6. Close, reopen, and read the three values back. ----
    await tester.runAsync(() => cubit.close(force: true));
    expect(cubit.isClosed, isTrue);

    final reopened = _buildCubit(schema);
    addTearDown(() async {
      if (!reopened.isClosed) {
        await reopened.close(force: true);
      }
    });
    await tester.runAsync(() => reopened.openPath(createdRoot));
    expect(reopened.state, isA<SaveSessionReady>());
    expect(reopened.lastOpenResult, isA<ParseUnverified>());
    final reopenedProject = reopened.openProject;
    expect(reopenedProject, isNotNull);
    final values = (
      maxLife: _intOf(reopenedProject!, maxLifeId),
      flag: _boolOf(reopenedProject, flagId),
      tokenStock: _intOf(reopenedProject, tokenStockId),
    );
    expect(values.maxLife, 24);
    expect(values.flag, isTrue);
    expect(values.tokenStock, 5);
    stdout.writeln(
      '[e2e] reopen maxLife=${values.maxLife} flag=${values.flag} '
      'tokenStock=${values.tokenStock}',
    );

    // ---- 7. Save As, then reopen the export through a fresh cubit. ----
    final exportRoot = '${scratch.path}/export';
    await tester.runAsync(() => reopened.saveAs(exportRoot));
    await tester.pumpAndSettle();
    final asState = reopened.state;
    expect(asState, isA<SaveSessionSaved>());
    final asSaved = asState as SaveSessionSaved;
    expect(asSaved.mode, ExportMode.saveAs);
    expect(asSaved.path, exportRoot);

    final exportedProgressFile = File('$exportRoot/slot_00/progress.sav');
    final exportedCaptionFile = File('$exportRoot/slot_00/caption.sav');
    expect(exportedProgressFile.existsSync(), isTrue);
    expect(exportedCaptionFile.existsSync(), isTrue);
    final exportedProgress = exportedProgressFile.readAsBytesSync();
    final exportedCaption = exportedCaptionFile.readAsBytesSync();
    expectByteIdentical(exportedProgress, savedProgress);
    expectByteIdentical(exportedCaption, savedCaption);
    expectByteIdentical(exportedCaption, originalCaption);
    stdout.writeln(
      '[e2e] saveAs path=$exportRoot progress=${exportedProgress.length} '
      'caption=${exportedCaption.length} identical=true',
    );

    final exported = _buildCubit(schema);
    addTearDown(() async {
      if (!exported.isClosed) {
        await exported.close(force: true);
      }
    });
    await tester.runAsync(() => exported.openPath(exportRoot));
    expect(exported.state, isA<SaveSessionReady>());
    final exportedProject = exported.openProject;
    expect(exportedProject, isNotNull);
    expect(_intOf(exportedProject!, maxLifeId), 24);
    expect(_boolOf(exportedProject, flagId), isTrue);
    expect(_intOf(exportedProject, tokenStockId), 5);
    stdout.writeln(
      '[e2e] exportReopen maxLife=24 flag=true tokenStock=5 ready=true',
    );

    expect(tester.takeException(), isNull);
  });
}

/// Selects [tab] and lets its lazy page build settle.
///
/// The catalogue tabs start a FutureBuilder on first build; one real-async
/// delay lets a platform-message future finish, and the following settle paints
/// the resolved page. The fake clock alone cannot complete that chain.
Future<void> _showTab(
  WidgetTester tester,
  ShellCubit shell,
  ShellTab tab,
) async {
  shell.selectTab(tab);
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pumpAndSettle();
}

/// Types [query] into the displayed EditTable's search box and settles.
Future<void> _searchEditTable(WidgetTester tester, String query) async {
  final search = find.byKey(EditTable.searchFieldKey);
  expect(search, findsOneWidget);
  await tester.enterText(search, query);
  await tester.pumpAndSettle();
}

/// Builds a session cubit exactly as `lib/main.dart` does.
SaveSessionCubit _buildCubit(GameDataSchema schema) {
  final engine = createProgressEngine();
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

/// The stable `progress.<hash8>` id the layout assigns to [name].
FieldId _fieldId(GameDataSchema schema, String name) {
  final definition = schema.byNameOnDisk(name);
  final hash = definition?.hash;
  if (hash == null) {
    throw StateError('schema has no on-disk $name');
  }
  return FieldId('progress.${hash.toRadixString(16).padLeft(8, '0')}');
}

/// The 4-byte value word of [name]: `0x28 + 8 * recordIndex + 4`.
ByteSpan _valueSpan(GameDataSchema schema, String name) {
  final index = schema.byNameOnDisk(name)?.recordIndex;
  if (index == null) {
    throw StateError('schema has no on-disk $name record');
  }
  return ByteSpan(0x28 + 8 * index + 4, 4);
}

/// Reads [id] as an integer from [project].
int _intOf(SaveProject project, FieldId id) {
  final value = project.document(progressSlotId)?.field(id)?.value;
  if (value is! IntValue) {
    throw StateError('$id is not an integer field: $value');
  }
  return value.value;
}

/// Reads [id] as a boolean from [project].
bool _boolOf(SaveProject project, FieldId id) {
  final value = project.document(progressSlotId)?.field(id)?.value;
  if (value is! BoolValue) {
    throw StateError('$id is not a boolean field: $value');
  }
  return value.value;
}

/// Prints one `[e2e]` line per applied edit, with the measured span.
void _reportEdit(
  String tab,
  String name,
  FieldId id,
  ByteSpan span,
  int from,
  int to,
) {
  stdout.writeln(
    '[e2e] edit tab=$tab field=$name id=${id.value} '
    'span=${_hexOffset(span.offset)}..${_hexOffset(span.end)} '
    'from=$from to=$to',
  );
}

/// One domain-specific finder per tab, never the empty state.
Finder _contentFor(ShellTab tab) => switch (tab) {
  ShellTab.overview => find.byKey(const Key('overview-life')),
  ShellTab.playerWorld => find.text('Player_Pos_For_Map'),
  ShellTab.inventory => find.text('Acquisition'),
  ShellTab.equipment => find.text('Equipped slots'),
  ShellTab.resources => find.byKey(ResourcesTab.lifeFieldKey),
  ShellTab.progression => find.text('HavePlayedEvent.BancChangeArrive'),
  ShellTab.dungeons => find.text('DungeonInfo.DodongoCavern.IsGetCompass'),
  ShellTab.collectibles => find.text('GatheringTokenGold_Father_BacktoHuman'),
  ShellTab.flags => find.textContaining('Named Bool fields'),
  ShellTab.advancedData => find.byKey(AdvancedDataTab.editorKey),
  ShellTab.settings => find.byKey(SettingsTab.backupPolicyKey),
};

/// Human description of [_contentFor] for the `[e2e]` evidence line.
String _contentLabel(ShellTab tab) => switch (tab) {
  ShellTab.overview => 'overview-life tile',
  ShellTab.playerWorld => 'Player_Pos_For_Map field row',
  ShellTab.inventory => 'Acquisition section',
  ShellTab.equipment => 'Equipped slots section',
  ShellTab.resources => 'resources-life editor',
  ShellTab.progression => 'HavePlayedEvent.BancChangeArrive row',
  ShellTab.dungeons => 'DungeonInfo.DodongoCavern.IsGetCompass row',
  ShellTab.collectibles => 'GatheringTokenGold_Father_BacktoHuman row',
  ShellTab.flags => 'named Bool section label',
  ShellTab.advancedData => 'raw hex editor',
  ShellTab.settings => 'backup-policy control',
};

String _hexOffset(int offset) => '0x${offset.toRadixString(16)}';
