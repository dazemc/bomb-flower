import 'dart:typed_data';

import 'package:bomb_flower/domain/core/core.dart';
import 'package:bomb_flower/presentation/dialogs/compare_save_dialog.dart';
import 'package:bomb_flower/presentation/widgets/data/provenance_badge.dart';
import 'package:bomb_flower/presentation/widgets/data/stone_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'dialog_test_support.dart';

/// The only slot these synthetic projects contain.
const SaveSlotId slot = SaveSlotId('slot_00');

/// Declared slot length, large enough for every span used below.
const int saveLength = 128;

typedef _FieldSpec = ({
  FieldDescriptor descriptor,
  FieldValue original,
  FieldValue current,
  bool dirty,
});

/// A two-byte integer descriptor at [offset]; ids stay unique per offset.
FieldDescriptor _descriptorAt(int offset, String label) {
  return FieldDescriptor(
    FieldId('field.0x${offset.toRadixString(16)}'),
    slot,
    label,
    FieldKind.integer,
    ByteSpan(offset, 2),
    FieldConfidence.verified,
    'test/compare_save_dialog_test.dart#0x${offset.toRadixString(16)}',
  );
}

/// Builds a fake project whose byte diff is real, with no I/O or engine.
///
/// [changedOffsets] are the current bytes that differ from the zeroed original,
/// so `SaveProject.changedSpans` computes genuine coalesced runs.
SaveProject _buildProject({
  required List<_FieldSpec> fields,
  List<int> changedOffsets = const <int>[],
  bool preserveUnknown = true,
}) {
  final originalBytes = Uint8List(saveLength);
  final currentBytes = Uint8List.fromList(originalBytes);
  for (final offset in changedOffsets) {
    currentBytes[offset] = 0x7f;
  }

  final slotLayout = SaveSlotLayout(
    slot,
    'slot_00/progress.sav',
    <FieldDescriptor>[for (final spec in fields) spec.descriptor],
    expectedLength: saveLength,
  );
  final layout = LayoutDescriptor('cmp-layout', 7, <SaveSlotLayout>[
    slotLayout,
  ], minimumVersion: 5);
  final original = SaveSnapshot(slot, 0, ByteRegion.fromBytes(originalBytes));
  final current = SaveSnapshot(slot, 1, ByteRegion.fromBytes(currentBytes));
  final document = SaveDocument(
    slot,
    slotLayout,
    current,
    <SaveField<FieldValue>>[
      for (final spec in fields)
        SaveField<FieldValue>(
          spec.descriptor,
          spec.current,
          spec.original,
          isDirty: spec.dirty,
        ),
    ],
  );

  return SaveProject(
    'cmp',
    '/save',
    '/save.bombflower-original',
    layout,
    7,
    <SaveSlotId, SaveSnapshot>{slot: original},
    <SaveSlotId, SaveDocument>{slot: document},
    <SaveSlotId, int>{slot: original.fingerprint},
    EditHistory(),
    EditLog(const <EditRecord>[]),
    preserveUnknown: preserveUnknown,
  );
}

void main() {
  testWidgets('compares two changed fields in ascending offset order', (
    tester,
  ) async {
    // The document lists the higher offset first on purpose.
    final project = _buildProject(
      changedOffsets: const <int>[0x0a, 0x0b, 0x14, 0x15],
      fields: <_FieldSpec>[
        (
          descriptor: _descriptorAt(0x14, 'Armor'),
          original: const IntValue(5),
          current: const IntValue(7),
          dirty: true,
        ),
        (
          descriptor: _descriptorAt(0x0a, 'Health'),
          original: const IntValue(100),
          current: const IntValue(42),
          dirty: true,
        ),
      ],
    );

    await launchDialog<void>(
      tester,
      (context) => CompareSaveDialog.show(context, project: project),
      size: const Size(1100, 700),
    );

    expect(find.text('2 fields changed'), findsOneWidget);
    expect(find.text('4 bytes changed'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    expect(
      find.descendant(
        of: find.byKey(StoneTable.rowKey(0)),
        matching: find.text('Health'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(StoneTable.rowKey(1)),
        matching: find.text('Armor'),
      ),
      findsOneWidget,
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('compare-span-0'))).data,
      '0xa +2',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('compare-span-1'))).data,
      '0x14 +2',
    );

    final originalLabel = tester
        .widget<Text>(find.byKey(const Key('compare-original-fingerprint')))
        .data!;
    final currentLabel = tester
        .widget<Text>(find.byKey(const Key('compare-current-fingerprint')))
        .data!;
    expect(RegExp(r'^Original 0x[0-9a-f]{8}$').hasMatch(originalLabel), isTrue);
    expect(RegExp(r'^Current 0x[0-9a-f]{8}$').hasMatch(currentLabel), isTrue);

    // The detail strip starts on the first (lowest-offset) row.
    expect(
      tester.widget<Text>(find.byKey(const Key('compare-field-span'))).data,
      '0xa +2',
    );
    expect(
      tester
          .widget<ProvenanceBadge>(find.byKey(const Key('compare-provenance')))
          .source,
      _descriptorAt(0x0a, 'Health').source,
    );

    await tester.tap(find.byKey(StoneTable.rowKey(1)));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('compare-field-span'))).data,
      '0x14 +2',
    );
    expect(
      tester
          .widget<ProvenanceBadge>(find.byKey(const Key('compare-provenance')))
          .source,
      _descriptorAt(0x14, 'Armor').source,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders only the empty state when nothing changed', (
    tester,
  ) async {
    final project = _buildProject(
      fields: <_FieldSpec>[
        (
          descriptor: _descriptorAt(0x0a, 'Health'),
          original: const IntValue(100),
          current: const IntValue(100),
          dirty: false,
        ),
      ],
    );

    await launchDialog<void>(
      tester,
      (context) => CompareSaveDialog.show(context, project: project),
    );

    expect(
      find.text('No changes yet — this save matches the original.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('compare-empty')), findsOneWidget);
    expect(find.byKey(const Key('compare-field-table')), findsNothing);
    expect(find.byKey(const Key('compare-byte-spans')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('counts one changed field and its two bytes', (tester) async {
    final project = _buildProject(
      changedOffsets: const <int>[0x0a, 0x0b],
      fields: <_FieldSpec>[
        (
          descriptor: _descriptorAt(0x0a, 'Health'),
          original: const IntValue(100),
          current: const IntValue(42),
          dirty: true,
        ),
      ],
    );

    await launchDialog<void>(
      tester,
      (context) => CompareSaveDialog.show(context, project: project),
      size: const Size(1100, 700),
    );

    expect(find.text('1 field changed'), findsOneWidget);
    expect(find.text('2 bytes changed'), findsOneWidget);
    expect(find.byKey(const Key('compare-field-table')), findsOneWidget);
    expect(find.byKey(StoneTable.rowKey(0)), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('compare-span-0'))).data,
      '0xa +2',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out five changed fields at 1100x700 without overflow', (
    tester,
  ) async {
    final project = _buildProject(
      changedOffsets: const <int>[
        0x0a,
        0x0b,
        0x14,
        0x15,
        0x1e,
        0x1f,
        0x28,
        0x29,
        0x32,
        0x33,
      ],
      fields: <_FieldSpec>[
        for (var i = 0; i < 5; i++)
          (
            descriptor: _descriptorAt(0x0a * (i + 1), 'Field ${i + 1}'),
            original: IntValue(i),
            current: IntValue(i + 10),
            dirty: true,
          ),
      ],
    );

    final launch = await launchDialog<void>(
      tester,
      (context) => CompareSaveDialog.show(context, project: project),
      size: const Size(1100, 700),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('compare-field-table')), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(StoneTable.rowKey(i)), findsOneWidget, reason: '$i');
    }

    await tester.tap(find.byKey(const Key('compare-close')));
    await tester.pumpAndSettle();

    expect(launch.isCompleted, isTrue);
    expect(tester.takeException(), isNull);
  });
}
