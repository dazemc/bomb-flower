import 'dart:io';

import 'package:bomb_flower/domain/catalogue/actor_catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('verified actor catalogue', () {
    late ActorCatalogue catalogue;

    setUpAll(() async {
      final file = File('assets/catalogue/actors.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run `dart run tool/gen_catalogues.dart` to create it',
      );
      catalogue = loadActorCatalogue(await file.readAsString());
    });

    test('loads 19 equipment, 54 items, 12 songs and 1 bottle', () {
      expect(catalogue.equipment, hasLength(19));
      expect(catalogue.items, hasLength(54));
      expect(catalogue.songs, hasLength(12));
      expect(catalogue.bottles, hasLength(1));
      expect(catalogue.all, hasLength(86));
      expect(
        catalogue.equipment.where((entry) => entry.kind == 'sword'),
        hasLength(4),
      );
      expect(
        catalogue.equipment.where((entry) => entry.kind == 'mask'),
        hasLength(8),
      );
      expect(
        catalogue.songs.every((entry) => entry.name.startsWith('Item_Melody_')),
        isTrue,
      );
      expect(catalogue.bottles.single.name, 'Item_Bottle');
      expect(catalogue.bottles.single.displayName, 'Empty Bottle');
    });

    test('has no duplicate game strings and every label is cited', () {
      final names = catalogue.all.map((entry) => entry.name).toList();
      expect(names.toSet(), hasLength(names.length));
      for (final entry in catalogue.all) {
        expect(entry.name, isNotEmpty);
        expect(entry.displayName, isNotEmpty);
        expect(entry.labelInferred, isFalse, reason: entry.name);
        expect(entry.sourceLine, greaterThan(0), reason: entry.name);
        expect(
          RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(entry.name),
          isTrue,
          reason: entry.name,
        );
      }
    });

    test('resolves exact equipment strings and rejects junk', () {
      final kokiri = catalogue.withEquipment('Weapon_Sword_Kokiri');
      expect(kokiri, isNotNull);
      expect(kokiri!.displayName, 'Kokiri Sword');
      expect(kokiri.kind, 'sword');
      expect(kokiri.section, 'Equipment');
      expect(kokiri.stackable, isFalse);

      final dekuShield = catalogue.withEquipment('Weapon_Shield_Deku');
      expect(dekuShield?.displayName, 'Deku Shield');
      expect(catalogue.isValidEquipmentString('Weapon_Sword_Kokiri'), isTrue);
      expect(catalogue.isValidEquipmentString('Weapon_Shield_Deku'), isTrue);
      expect(catalogue.isValidEquipmentString('Item_Ocarina_Fairy'), isFalse);
      expect(catalogue.withEquipment('Item_Ocarina_Fairy'), isNull);
      expect(catalogue.isValidEquipmentString("'; DROP TABLE"), isFalse);
      expect(
        catalogue.isValidEquipmentString('Weapon_Sword_Kokiri;--'),
        isFalse,
      );
      expect(catalogue.isValidEquipmentString('Weapon_Sword_NotReal'), isFalse);
      expect(catalogue.isValidEquipmentString(''), isFalse);
      expect(catalogue.isValidEquipmentString('weapon_sword_kokiri'), isFalse);
    });

    test('resolves exact item, song and bottle strings', () {
      expect(
        catalogue.byName('Item_Ocarina_Fairy')?.displayName,
        'Fairy Ocarina',
      );
      expect(
        catalogue.byName('Item_Ocarina_Time')?.displayName,
        'Ocarina of Time',
      );
      expect(catalogue.byName('Item_Longshot')?.displayName, 'Longshot');
      expect(
        catalogue.byName('Item_Melody_ZeldaLullaby')?.displayName,
        "Zelda's Lullaby",
      );
      expect(catalogue.byName('Item_Bottle')?.displayName, 'Empty Bottle');
      expect(catalogue.isValidActorString('Item_Ocarina_Fairy'), isTrue);
      expect(catalogue.isValidActorString("'; DROP TABLE"), isFalse);
      expect(catalogue.byName('Item_NotReal'), isNull);
    });

    test('labelsFor matches bucket names and entry kinds', () {
      expect(catalogue.labelsFor('sword'), <String>[
        "Biggoron's Sword",
        "Giant's Knife",
        'Kokiri Sword',
        'Master Sword',
      ]);
      expect(catalogue.labelsFor('song'), hasLength(12));
      expect(catalogue.labelsFor('SONGS'), hasLength(12));
      expect(catalogue.labelsFor('equipment'), hasLength(19));
      expect(catalogue.labelsFor('items'), hasLength(54));
      expect(catalogue.labelsFor('bottles'), <String>['Empty Bottle']);
      expect(catalogue.labelsFor('mask'), hasLength(8));
      expect(catalogue.labelsFor('not-a-kind'), isEmpty);
      expect(catalogue.labelsFor('sword'), contains('Kokiri Sword'));
    });

    test('search is case- and diacritic-insensitive over names and labels', () {
      expect(
        catalogue.search('kókírí').map((entry) => entry.displayName),
        contains('Kokiri Sword'),
      );
      expect(
        catalogue.search('OCARINA').map((entry) => entry.displayName),
        containsAll(<String>['Fairy Ocarina', 'Ocarina of Time']),
      );
      expect(
        catalogue.search('zelda').map((entry) => entry.displayName),
        containsAll(<String>["Zelda's Letter", "Zelda's Lullaby"]),
      );
      expect(catalogue.search('').length, 86);
      expect(catalogue.search('definitely-not-an-actor'), isEmpty);
    });

    test('stackable flags follow the header quantity kind', () {
      expect(catalogue.byName('Item_Bomb')?.stackable, isTrue);
      expect(catalogue.byName('Item_Bottle')?.stackable, isTrue);
      expect(catalogue.byName('Weapon_Sword_Kokiri')?.stackable, isFalse);
      expect(catalogue.byName('Item_Stone_Forest')?.stackable, isFalse);
    });

    test('asset provenance keeps its source and exclusions', () {
      final provenance = catalogue.provenance;
      expect(provenance['source'], isA<Map<String, Object?>>());
      expect(
        (provenance['source']! as Map<String, Object?>)['path'],
        'Longshot:gpu/vk/oot_cheat_items.h',
      );
      expect(provenance['excluded'], isA<List<Object?>>());
    });
  });
}
