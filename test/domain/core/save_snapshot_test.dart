import 'package:bomb_flower/domain/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const slot = SaveSlotId('slot_00');

  group('SaveSnapshot', () {
    test('replace bumps revision and preserves prior content', () {
      final region = ByteRegion.fromBytes(<int>[1, 2, 3]);
      final snapshot = SaveSnapshot(slot, 4, region);
      final edited = snapshot.replace(const ByteSpan(1, 1), <int>[9]);

      expect(edited.slot, slot);
      expect(edited.revision, 5);
      expect(edited.materialize(), <int>[1, 9, 3]);
      expect(snapshot.materialize(), <int>[1, 2, 3]);
      expect(edited.length, 3);
      expect(edited.fingerprint, edited.content.fingerprint);
    });

    test('equality is revision identity, not deep bytes', () {
      final a = ByteRegion.fromBytes(<int>[1, 2, 3]);
      final b = ByteRegion.fromBytes(<int>[1, 2, 3]);
      final first = SaveSnapshot(slot, 1, a);

      expect(first, SaveSnapshot(slot, 1, a));
      expect(first.hashCode, SaveSnapshot(slot, 1, a).hashCode);
      expect(first == SaveSnapshot(slot, 1, b), isFalse);
      expect(first == SaveSnapshot(slot, 2, a), isFalse);
      expect(first == SaveSnapshot(const SaveSlotId('other'), 1, a), isFalse);
    });

    test('sameBytesAs compares bytes explicitly', () {
      final a = ByteRegion.fromBytes(<int>[1, 2, 3]);
      final b = ByteRegion.fromBytes(<int>[1, 2, 3]);
      final c = ByteRegion.fromBytes(<int>[1, 9, 3]);

      expect(a.sameBytesAs(b), isTrue);
      expect(a.sameBytesAs(c), isFalse);
    });
  });
}
