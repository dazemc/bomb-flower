import 'package:bomb_flower/presentation/theme/bomb_flower_theme.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_slider.dart';
import 'package:bomb_flower/presentation/widgets/controls/brass_toggle.dart';
import 'package:bomb_flower/presentation/widgets/controls/hex_value_field.dart';
import 'package:bomb_flower/presentation/widgets/controls/labelled_field.dart';
import 'package:bomb_flower/presentation/widgets/controls/numeric_field.dart';
import 'package:bomb_flower/presentation/widgets/controls/rune_checkbox.dart';
import 'package:bomb_flower/presentation/widgets/controls/toast.dart';
import 'package:bomb_flower/presentation/widgets/data/provenance_badge.dart';
import 'package:bomb_flower/presentation/widgets/data/stat_tile.dart';
import 'package:bomb_flower/presentation/widgets/data/stone_table.dart';
import 'package:bomb_flower/presentation/widgets/selectors/item_grid.dart';
import 'package:bomb_flower/presentation/widgets/selectors/searchable_select.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _columns = <StoneTableColumn<String>>[
  StoneTableColumn<String>(label: 'Name', cell: _identity, flex: 2),
  StoneTableColumn<String>(label: 'Notes', cell: _identity, flex: 2),
];

String _identity(String row) => row;

Future<void> pumpMatrix(
  WidgetTester tester, {
  required double width,
  required GlobalKey<ToastHostState> toastKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: BombFlowerThemeData.build(),
      builder: (context, appChild) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: appChild!,
        );
      },
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const BrassToggle(
                value: true,
                onChanged: _noopToggle,
                label:
                    'Automatically equip the selected shield on save load and '
                    'after every dungeon transition',
                description: 'A long description that must wrap at every supported width.',
              ),
              const SizedBox(height: 20),
              const RuneCheckbox(
                value: true,
                onChanged: _noopCheckbox,
                label:
                    'Show every raw hexadecimal byte in the advanced data '
                    'inspector',
              ),
              const SizedBox(height: 20),
              const BrassSlider(
                value: 40,
                min: 0,
                max: 100,
                divisions: 10,
                label:
                    'Dungeon completion percentage including optional tokens',
                onChanged: _noopSlider,
              ),
              const SizedBox(height: 20),
              const LabelledField(
                label: 'Optional dungeon completion flag stored in the scene table',
                help: 'A long help sentence that stays readable.',
                modified: true,
                invalid: true,
                child: Text('control'),
              ),
              const SizedBox(height: 20),
              const NumericField(
                value: 65535,
                min: 0,
                max: 65535,
                step: 10,
                label:
                    'Maximum carry capacity including every purchased wallet '
                    'upgrade',
                unit: 'rupees',
                onChanged: _noopNumber,
              ),
              const SizedBox(height: 20),
              const HexValueField(
                value: 0x1234,
                width: 4,
                label: 'Raw actor definition pointer offset in the scene table',
                onChanged: _noopHex,
              ),
              const SizedBox(height: 20),
              SearchableSelect<String>(
                items: const <String>[
                  'Kokiri Sword',
                  'Kokiri Shield',
                  'Master Sword',
                  'Deku Nut',
                  'Ocarina of Time',
                ],
                itemLabel: _identity,
                label: 'Inventory item',
                emptyMessage: 'No items',
                onChanged: _noopString,
              ),
              const SizedBox(height: 20),
              ItemGrid<String>(
                items: <String>[
                  for (var index = 0; index < 24; index++)
                    'Long catalogue item $index',
                ],
                selectedIndex: 0,
                onSelected: _noopIndex,
              ),
              const SizedBox(height: 20),
              StoneTable<String>(
                columns: _columns,
                rows: const <String>[
                  'Kokiri Forest and the Lost Woods beyond the stepping stones',
                  'A second row of deliberately long catalogue text for wrapping',
                ],
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 260,
                child: StatTile(
                  label: 'Total collected gold skulltula tokens across every region',
                  value: '123,456,789',
                  unit: 'tokens',
                  severity: StatSeverity.info,
                  help: 'A deliberately long help sentence.',
                ),
              ),
              const SizedBox(height: 20),
              const ProvenanceBadge(
                level: ProvenanceLevel.inferred,
                source:
                    'Inferred from the actor catalogue entry and the scene '
                    'table offset pending a verified fixture.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 220,
                child: ToastHost(key: toastKey, child: const SizedBox.expand()),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final width in <double>[900, 1100, 1360]) {
    testWidgets('all primitives fit ${width.toInt()} px at 1.3x', (
      tester,
    ) async {
      final toastKey = GlobalKey<ToastHostState>();
      await pumpMatrix(tester, width: width, toastKey: toastKey);
      toastKey.currentState!.show(
        'The sidecar checksum could not be verified after export.',
        tone: StoneToastTone.warning,
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'a primitive overflowed at ${width.toInt()} px and 1.3x',
      );
    });
  }
}

void _noopToggle(bool value) {}
void _noopCheckbox(bool? value) {}
void _noopSlider(double value) {}
void _noopNumber(num value) {}
void _noopHex(int value) {}
void _noopString(String value) {}
void _noopIndex(int value) {}
